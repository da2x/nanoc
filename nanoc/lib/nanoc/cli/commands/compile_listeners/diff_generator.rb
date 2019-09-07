# frozen_string_literal: true

module Nanoc::CLI::Commands::CompileListeners
  class DiffGenerator < Abstract
    class Differ
      def initialize(path, str_a, str_b)
        @path = path
        @str_a = str_a
        @str_b = str_b
      end

      def call
        run
      end

      private

      def run
        lines_a = @str_a.lines.map(&:chomp)
        lines_b = @str_b.lines.map(&:chomp)

        diffs = Diff::LCS.diff(lines_a, lines_b)

        # Find hunks
        hunks = []
        file_length_difference = 0
        diffs.each do |piece|
          hunk = Diff::LCS::Hunk.new(lines_a, lines_b, piece, 3, file_length_difference)
          file_length_difference = hunk.file_length_difference
          hunks << hunk
        end

        # Merge hunks
        merged_hunks = []
        hunks.each do |hunk|
          merged = merged_hunks.any? && hunk.merge(merged_hunks.last)
          merged_hunks << hunk unless merged
        end

        # Output hunks
        output = +''
        output << "--- #{@path}\n"
        output << "+++ #{@path}\n"
        merged_hunks.each do |hunk|
          output << hunk.diff(:unified) << "\n"
        end

        output
      end
    end

    # @see Listener#enable_for?
    def self.enable_for?(command_runner, site)
      site.config[:enable_output_diff] || command_runner.options[:diff]
    end

    # @see Listener#start
    def start
      setup_diffs
      old_contents = {}

      on(:rep_write_started) do |rep, path|
        old_contents[rep] = File.file?(path) ? File.read(path) : nil
      end

      on(:rep_write_ended) do |rep, binary, path, _is_created, _is_modified|
        unless binary
          new_contents = File.file?(path) ? File.read(path) : nil
          if old_contents[rep] && new_contents
            generate_diff_for(path, old_contents[rep], new_contents)
          end
          old_contents.delete(rep)
        end
      end
    end

    # @see Listener#stop
    def stop
      teardown_diffs
    end

    protected

    def setup_diffs
      @diff_lock    = Mutex.new
      @diff_threads = []
      FileUtils.rm('output.diff') if File.file?('output.diff')
    end

    def teardown_diffs
      @diff_threads.each(&:join)
    end

    def generate_diff_for(path, old_content, new_content)
      return if old_content == new_content

      @diff_threads << Thread.new do
        # Simplify path
        # FIXME: do not depend on working directory
        if path.start_with?(Dir.getwd)
          path = path[(Dir.getwd.size + 1)..path.size]
        end

        # Generate diff
        diff = Differ.new(path, old_content, new_content).call

        # Write diff
        @diff_lock.synchronize do
          File.open('output.diff', 'a') { |io| io.write(diff) }
        end
      end
    end
  end
end
