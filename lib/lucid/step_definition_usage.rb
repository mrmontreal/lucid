module Lucid
  # Only used for keeping track of available and invoked step definitions.
  class StepDefinitionUsage
    attr_reader :regexp_source, :file_colon_line

    def initialize(regexp_source, file_colon_line)
      @regexp_source, @file_colon_line = regexp_source, file_colon_line
    end

    def eql?(o)
      regexp_source == o.regexp_source && file_colon_line == o.file_colon_line
    end

    def hash
      regexp_source.hash + 31*file_colon_line.hash
    end
  end
end
