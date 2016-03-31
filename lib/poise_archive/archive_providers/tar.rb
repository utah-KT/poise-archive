#
# Copyright 2016, Noah Kantrowitz
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'fileutils'
require 'rubygems/package'
require 'zlib'

require 'poise_archive/archive_providers/base'


module PoiseArchive
  module ArchiveProviders
    # The `tar` provider class for `poise_archive` to install from tar archives.
    #
    # @see PoiseArchive::Resources::PoiseArchive::Resource
    # @provides poise_archive
    class Tar < Base
      provides_extension(/\.t(ar|gz|bz)/)

      # Hack that GNU tar uses for paths over 100 bytes.
      #
      # @api private
      # @see #unpack_tar
      TAR_LONGLINK = '././@LongLink'

      private

      def unpack_archive
        install_prereqs
        unpack_tar
      end

      # Install any needed prereqs.
      #
      # @return [void]
      def install_prereqs
        # Tar and Gzip come with Ruby.
        if new_resource.path =~ /\.t?bz/
          # This isn't working yet. TODO.
          raise NotImplementedError
          # Install and load rbzip2 for BZip2 handling.
          notifying_block do
            chef_gem 'rbzip2'
          end
        end
      end

      # Unpack the archive.
      #
      # @return [void]
      def unpack_tar
        tar_each do |entry|
          entry_name = if entry.full_name == TAR_LONGLINK
            entry.read.strip
          else
            entry.full_name
          end.split(/\//).drop(new_resource.strip_components).join('/')
          next if entry_name.empty?
          dest = ::File.join(new_resource.destination, entry_name)
          if entry.directory?
            Dir.mkdir(dest, entry.header.mode)
          elsif entry.file?
            ::File.open(dest, 'wb', entry.header.mode) do |dest_f|
              while buf = entry.read(4096)
                dest_f.write(buf)
              end
            end
          elsif entry.symlink?
            ::File.symlink(entry.header.linkname, dest)
          else
            raise RuntimeError.new("Unknown tar entry type #{entry.header.typeflag.inspect} in #{new_resource.path}")
          end
          FileUtils.chown(new_resource.user, new_resource.group, dest)
        end
      end

      # Sequence the opening, iteration, and closing.
      #
      # @param block [Proc] Block to process each tar entry.
      # @return [void]
      def tar_each(&block)
        # In case of extreme weirdness where this happens twice.
        close_file!
        open_file!
        @tar_reader.each(&block)
      ensure
        close_file!
      end

      # Open a file handle of the correct flavor.
      #
      # @return [void]
      def open_file!
        @raw_file = ::File.open(new_resource.path, 'rb')
        @file = case new_resource.path
        when /\.tar$/
          nil # So it uses @raw_file instead.
        when /\.t?gz/
          Zlib::GzipReader.wrap(@raw_file)
        when /\.t?bz/
          require 'rbzip2'
          # This can't take a block, hence the gross non-block forms for everything.
          RBzip2::Decompressor.new(@raw_file)
        else
          raise RuntimeError.new("Unknown or unsupported file extension for #{new_resource.path}")
        end
        @tar_reader = Gem::Package::TarReader.new(@file || @raw_file)
      end

      # Close all the various file handles.
      #
      # @return [void]
      def close_file!
        if @tar_reader
          @tar_reader.close
          @tar_reader = nil
        end
        if @file
          @file.close
          @file = nil
        end
        if @raw_file
          @raw_file.close unless @raw_file.closed?
          @raw_file = nil
        end
      end

    end
  end
end
