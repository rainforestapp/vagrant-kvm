# Utility class to translate ovf definition to libvirt XML
# and manage XML formatting for libvirt interaction
# Not a full OVF converter, only the minimal needed definition
require "rexml/document"

module VagrantPlugins
  module ProviderKvm
    module Util
      class VmDefinition
        include Errors
        include DefinitionAttributes

        def self.list_interfaces(definition)
          nics = []
          doc = REXML::Document.new definition
          # look for user mode interfaces
          doc.elements.each("//devices/interface[@type='user']") do |item|
            nics << {:type => :user, :network => nil }
          end
          # look for interfaces on virtual network
          doc.elements.each("//devices/interface[@type='network']") do |item|
            nics << {
              :type => :network,
              :network => item.elements["source"].attributes["network"].to_s
            }
          end
          nics
        end

        def initialize(definition)
          self.attributes = {
            :uuid         => nil,
            :gui          => nil,
            :vnc_autoport => false,
            :vnc_password => nil,
            :network      => 'default',
            :network_model => 'virtio',
            :video_model  => 'cirrus'
          }
          doc = REXML::Document.new definition
          memory_unit = doc.elements["/domain/memory"].attributes["unit"]
          update({
            :name        => doc.elements["/domain/name"].text,
            :cpus        => doc.elements["/domain/vcpu"].text,
            :memory      => size_in_bytes(doc.elements["/domain/memory"].text,
                                  memory_unit), # always :memory is in bytes
            :arch        => doc.elements["/domain/os/type"].attributes["arch"],
            :machine_type => doc.elements["/domain/os/type"].attributes["machine"],
            :disk        => doc.elements["//devices/disk/source"].attributes["file"],
            :network     => doc.elements["//devices/interface/source"].attributes["network"],
            :network_model => :default,
            :mac         => format_mac(doc.elements["//devices/interface/mac"].attributes["address"]),
            :image_type  => doc.elements["//devices/disk/driver"].attributes["type"],
            :qemu_bin    => doc.elements["/domain/devices/emulator"].text,
            :video_model => doc.elements["/domain/devices/video/model"].attributes["type"],
            :disk_bus    => doc.elements["//devices/disk/target"].attributes["bus"],
            :volume_cache => doc.elements["//devices/disk/driver"].attributes["cache"],
          })
          model_node = doc.elements["//devices/interface/model"]
          if model_node
            update({
              :model_node  => model_node,
              :network_model => model_node.attributes["type"]
            })
          end
          if doc.elements["/domain/uuid"]
            update({:uuid => doc.elements["/domain/uuid"].text})
          end
          if doc.elements["//devices/graphics"]
            attrs = doc.elements["//devices/graphics"].attributes
            update({
              :gui          => attrs["type"] == 'vnc',
              :vnc_port     => attrs['port'].to_i,
              :vnc_autoport => attrs['autoport'] == 'yes',
              :vnc_password => attrs['passwd']
            })
          end
          kernel = doc.elements["//domain/os/kernel"]
          if kernel
            update({
              :kernel => kernel.text
            })
          end
          cpu_type = doc.elements["//domain/cpu/model"]
          if cpu_type
            update({
              :cpu_type => cpu_type.text
            })
          end
        end

        def as_xml
          if attributes[:qemu_bin]
            # user specified path of qemu binary
            qemu_bin_list = [attributes[:qemu_bin]]
          else
            # RedHat and Debian-based systems have different executable names
            # depending on version/architectures
            qemu_bin_list = ['/usr/bin/qemu-system-x86_64'] if get(:arch).match(/64$/)
            qemu_bin_list = ['/usr/bin/qemu-system-i386']   if get(:arch).match(/^i.86$/)
            qemu_bin_list += [ '/usr/bin/qemu-kvm', '/usr/bin/kvm' ]
          end

          qemu_bin = qemu_bin_list.detect { |binary| File.exists? binary }
          if not qemu_bin
            raise Errors::KvmNoQEMUBinary,
            :cause => attributes[:qemu_bin] ?
            "Vagrantfile (specified binary: #{attributes[:qemu_bin]})" : "QEMU installation"
          end

          xml = KvmTemplateRenderer.render("libvirt_domain",
                attributes.merge!(:memory_size => get_memory("KiB"),
                                  :memory_unit => "KiB")
                )
          xml
        end

        def get_memory(unit="bytes")
          size_from_bytes(get(:memory), unit)
        end

        def update(args={})
          args.each {|k,v|
            case k
            when :mac
              args[:mac] = format_mac(args[:mac])
            end
          }
          super(args)
        end

        # Takes a quantity and a unit
        # returns quantity in bytes
        # mib = true to use mebibytes, etc
        # defaults to false because ovf MB != megabytes
        def size_in_bytes(qty, unit, mib=false)
          qty = qty.to_i
          unit = unit.downcase
          if !mib
            case unit
            when "kb", "kilobytes"
              unit = "kib"
            when "mb", "megabytes"
              unit = "mib"
            when "gb", "gigabytes"
              unit = "gib"
            end
          end
          case unit
          when "b", "bytes"
            qty.to_s
          when "kb", "kilobytes"
            (qty * 1000).to_s
          when "kib", "kibibytes"
            (qty * 1024).to_s
          when "mb", "megabytes"
            (qty * 1000000).to_s
          when "m", "mib", "mebibytes"
            (qty * 1048576).to_s
          when "gb", "gigabytes"
            (qty * 1000000000).to_s
          when "g", "gib", "gibibytes"
            (qty * 1073741824).to_s
          else
            raise ArgumentError, "Unknown unit #{unit}"
          end
        end

        # Takes a qty and a unit
        # returns byte quantity in that unit
        def size_from_bytes(qty, unit)
          qty = qty.to_i
          case unit.downcase
          when "b", "bytes"
            qty.to_s
          when "kb", "kilobytes"
            (qty / 1000).to_s
          when "kib", "kibibytes"
            (qty / 1024).to_s
          when "mb", "megabytes"
            (qty / 1000000).to_s
          when "m", "mib", "mebibytes"
            (qty / 1048576).to_s
          when "gb", "gigabytes"
            (qty / 1000000000).to_s
          when "g", "gib", "gibibytes"
            (qty / 1073741824).to_s
          else
            raise ArgumentError, "Unknown unit #{unit}"
          end
        end

        def format_bool(v)
          v ? "yes" : "no"
        end

        def format_mac(mac)
          if mac.length == 12
            mac = mac[0..1] + ":" + mac[2..3] + ":" +
              mac[4..5] + ":" + mac[6..7] + ":" +
              mac[8..9] + ":" + mac[10..11]
          end
          mac
        end

      end
    end
  end
end
