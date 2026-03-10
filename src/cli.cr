require "./asciidoc_pdf"
require "option_parser"

module AsciidocPDF
  class CLI
    @input_file : String = ""
    @output_file : String = ""

    def initialize
    end

    def run(args : Array(String)) : Nil
      parse_options(args)

      if @input_file.empty?
        STDERR.puts "Error: no input file specified"
        STDERR.puts "Usage: asciidoc-to-pdf [options] INPUT_FILE"
        exit(1)
      end

      unless File.exists?(@input_file)
        STDERR.puts "Error: file not found: #{@input_file}"
        exit(1)
      end

      if @output_file.empty?
        @output_file = @input_file.gsub(/\.(adoc|asciidoc|asc|ad)$/, ".pdf")
        if @output_file == @input_file
          @output_file = @input_file + ".pdf"
        end
      end

      source = File.read(@input_file)
      converter = Converter.convert(source)

      if converter.warnings.size > 0
        converter.warnings.each do |w|
          STDERR.puts "WARNING: #{w}"
        end
      end

      converter.save(@output_file)
      puts "PDF written to #{@output_file}"
    end

    private def parse_options(args : Array(String)) : Nil
      OptionParser.parse(args) do |parser|
        parser.banner = "Usage: asciidoc-to-pdf [options] INPUT_FILE"

        parser.on("-o OUTPUT", "--output OUTPUT", "Output PDF file path") do |o|
          @output_file = o
        end

        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit(0)
        end

        parser.on("-v", "--version", "Show version") do
          puts "asciidoc-to-pdf 0.1.0 (crystal-pdf)"
          exit(0)
        end

        parser.unknown_args do |remaining|
          if remaining.size > 0
            @input_file = remaining[0]
          end
        end
      end
    end
  end
end

AsciidocPDF::CLI.new.run(ARGV)
