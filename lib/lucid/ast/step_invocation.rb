require 'lucid/errors'
require 'lucid/step_match'
require 'lucid/ast/table'
require 'gherkin/rubify'

module Lucid
  module AST
    class StepInvocation
      attr_writer :step_collection, :background
      attr_reader :name, :matched_cells, :status, :reported_exception
      attr_accessor :exception

      class << self
        SEVERITY = [:passed, :undefined, :pending, :skipped, :failed]
        def worst_status(statuses)
          SEVERITY[statuses.map{|status| SEVERITY.index(status)}.max]
        end
      end

      def initialize(step, name, multiline_arg, matched_cells)
        @step, @name, @multiline_arg, @matched_cells = step, name, multiline_arg, matched_cells
        status!(:skipped)
        @skip_invoke = @exception = @step_match = @different_table = @reported_exception = @background = nil
      end

      def background?
        @background
      end

      def skip_invoke!
        @skip_invoke = true
      end

      def accept(visitor)
        visitor.visit_step(self) do
          invoke(visitor.runtime, visitor.context)
          step_result.accept(visitor)
        end
      end

      def invoke(runtime, context)
        find_step_match!(runtime, context)
        unless @skip_invoke || context.dry_run? || @exception || @step_collection.exception
          @skip_invoke = true
          begin
            @step_match.invoke(@multiline_arg)
            runtime.after_step
            status!(:passed)
          rescue Pending => e
            failed(context, e, false)
            status!(:pending)
          rescue Undefined => e
            failed(context, e, false)
            status!(:undefined)
          rescue Lucid::AST::Table::Different => e
            @different_table = e.table
            failed(context, e, false)
            status!(:failed)
          rescue Exception => e
            failed(context, e, false)
            status!(:failed)
          end
        end
      end

      def find_step_match!(runtime, context)
        return if @step_match
        begin
          @step_match = runtime.step_match(@name)
        rescue Undefined => e
          failed(context, e, true)
          status!(:undefined)
          @step_match = NoStepMatch.new(@step, @name)
        rescue Ambiguous => e
          failed(context, e, false)
          status!(:failed)
          @step_match = NoStepMatch.new(@step, @name)
        end
        runtime.step_visited(self)
      end

      def failed(context, e, clear_backtrace)
        e.set_backtrace([]) if e.backtrace.nil? || clear_backtrace
        e.backtrace << @step.backtrace_line unless @step.backtrace_line.nil?
        e = filter_backtrace(e)
        @exception = e
        if(context.strict? || !(Undefined === e) || e.nested?)
          @reported_exception = e
        else
          @reported_exception = nil
        end
      end

      BACKTRACE_FILTER_PATTERNS = [/vendor\/rails|lib\/lucid|bin\/lucid:|lib\/rspec|gems\/|minitest|test\/unit|\/\.gem\//]

      if(Lucid::JRUBY)
        BACKTRACE_FILTER_PATTERNS << /org\/jruby/
      end

      PWD_PATTERN = /#{Regexp.escape(Dir.pwd)}\//m

      def filter_backtrace(e)
        return e if Lucid.use_full_backtrace
        e.backtrace.each{|line| line.gsub!(PWD_PATTERN, './')}

        filtered = (e.backtrace || []).reject do |line|
          BACKTRACE_FILTER_PATTERNS.detect { |p| line =~ p }
        end

        if ENV['LUCID_TRUNCATE_OUTPUT']
          # Strip off file locations
          filtered = filtered.map do |line|
            line =~ /(.*):in `/ ? $1 : line
          end
        end

        e.set_backtrace(filtered)
        e
      end

      def status!(status)
        @status = status
        @matched_cells.each do |cell|
          cell.status = status
        end
      end

      def previous
        @step_collection.previous_step(self)
      end

      def actual_keyword
        keywords = Keywords.new(language)
        if keywords.repeat_keyword?(keyword) && previous
          previous.actual_keyword
        else
          keyword == '* ' ? keywords.star_code_keyword : keyword
        end
      end

      class Keywords
        include Gherkin::Rubify

        def initialize(language)
          @language = language
        end

        def repeat_keyword?(keyword)
          repeat_keywords.index(keyword)
        end

        def star_code_keyword
          language.code_keywords.reject { |k| repeat_keywords.map(&:strip).include?(k) }.first
        end

        attr_reader :language
        private     :language

        private

        def repeat_keywords
          rubify([language.keywords('but'), language.keywords('and')]).flatten.uniq.reject{|kw| kw == '* '}
        end
      end

      def source_indent
        @step.feature_element.source_indent(text_length)
      end

      def text_length
        @step.text_length(@name)
      end

      def keyword
        @step.keyword
      end

      def multiline_arg
        @step.multiline_arg
      end

      def file_colon_line
        @step.file_colon_line
      end

      def dom_id
        @step.dom_id
      end

      def backtrace_line
        @step.backtrace_line
      end

      def language
        @step.language || raise("Language is required on #{@step}")
      end

      def gherkin_statement
        @step.gherkin_statement
      end

      def to_sexp
        [:step_invocation, @step.line, @step.keyword, @name, (@multiline_arg.nil? ? nil : @multiline_arg.to_sexp)].compact
      end

      private

      def step_result
        StepResult.new(
          keyword,
          @step_match,
          (@different_table || @multiline_arg),
          @status,
          @reported_exception,
          source_indent,
          @background,
          file_colon_line
        )
      end

    end
  end
end
