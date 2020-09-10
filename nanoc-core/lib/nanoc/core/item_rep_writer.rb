# frozen_string_literal: true

module Nanoc
  module Core
    class ItemRepWriter
      include Nanoc::Core::ContractsSupport
      include Nanoc::Core::Assertions::Mixin

      TMP_TEXT_ITEMS_DIR = 'text_items'

      def write_all(item_rep, compiled_content_store)
        written_paths = Set.new

        item_rep.snapshot_defs.map(&:name).each do |snapshot_name|
          write(item_rep, compiled_content_store, snapshot_name, written_paths)
        end
      end

      def write(item_rep, compiled_content_store, snapshot_name, written_paths)
        item_rep.raw_paths.fetch(snapshot_name, []).each do |raw_path|
          write_single(item_rep, compiled_content_store, snapshot_name, raw_path, written_paths)
        end
      end

      def write_single(item_rep, compiled_content_store, snapshot_name, raw_path, written_paths)
        assert Nanoc::Core::Assertions::PathIsAbsolute.new(path: raw_path)

        # Don’t write twice
        # TODO: test written_paths behavior
        return if written_paths.include?(raw_path)

        written_paths << raw_path

        # Create parent directory
        FileUtils.mkdir_p(File.dirname(raw_path))

        # Check if file will be created
        is_created = !File.file?(raw_path)

        # Notify
        Nanoc::Core::NotificationCenter.post(
          :rep_write_started, item_rep, raw_path
        )

        content = compiled_content_store.get(item_rep, snapshot_name)
        if content.binary?
          temp_path = content.filename
        else
          temp_path = temp_filename
          File.write(temp_path, content.string)
        end

        # Check whether content was modified
        is_modified = is_created || !FileUtils.identical?(raw_path, temp_path)

        # Notify ready for diff generation
        if !is_created && is_modified && !content.binary?
          Nanoc::Core::NotificationCenter.post(
            :rep_ready_for_diff, raw_path, File.read(raw_path, encoding: 'UTF-8'), content.string
          )
        end

        # Write
        # Clone or copy the file on a copy-on-write file system (APFS, Btrfs, XFS) if the
        # resulting and source files are identical.
        # Otherwise, hardlink the file or do a regular copy if unsupported.
        if is_modified
          written = false
          if Object.const_defined?('Clonefile')
            if !content.filename.nil? && FileUtils.identical?(content.filename, temp_path)
              Clonefile.auto(content.filename, raw_path)
              written = true
            end
          end
          unless written
            begin
              FileUtils.ln(temp_path, raw_path, force: true)
            rescue Errno::EXDEV, Errno::EACCES
              FileUtils.cp(temp_path, raw_path)
            end
          end
        end

        item_rep.modified = is_modified

        # Notify
        Nanoc::Core::NotificationCenter.post(
          :rep_write_ended, item_rep, content.binary?, raw_path, is_created, is_modified
        )
      end

      def temp_filename
        Nanoc::Core::TempFilenameFactory.instance.create(TMP_TEXT_ITEMS_DIR)
      end
    end
  end
end
