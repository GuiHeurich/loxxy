# frozen_string_literal: true

require 'strscan'
require 'rley'
require_relative '../datatype/all_datatypes'
require_relative 'literal'

module Loxxy
  module FrontEnd
    # A scanner (tokenizer) for the Lox language.
    # Reference material:
    #   https://craftinginterpreters.com/the-lox-language.html
    #   Section 4.2.1 Token types
    #   Appendix A1.2 Lexical Grammar
    # Responsibility: break input into a sequence of token objects.
    # The tokenizer should recognize:
    # Identifiers,
    # Number literals including single digit
    # String literals (quote delimited)
    # Delimiters: e.g. parentheses '(',  ')'
    # Separators: e.g. comma
    class Scanner
      # @return [StringScanner] Low-level input scanner
      attr_reader(:scanner)

      # @return [Integer] The current line number
      attr_reader(:lineno)

      # @return [Integer] Position of last start of line in the input
      attr_reader(:line_start)

      # One or two special character tokens.
      # These are enumerated in section 4.2.1 Token type
      @@lexeme2name = {
        '(' => 'LEFT_PAREN',
        ')' => 'RIGHT_PAREN',
        '{' => 'LEFT_BRACE',
        '}' => 'RIGHT_BRACE',
        ',' => 'COMMA',
        '.' => 'DOT',
        '-' =>  'MINUS',
        '+' => 'PLUS',
        ';' => 'SEMICOLON',
        '/' => 'SLASH',
        '*' => 'STAR',
        '!' => 'BANG',
        '!=' => 'BANG_EQUAL',
        '=' => 'EQUAL',
        '==' => 'EQUAL_EQUAL',
        '>' => 'GREATER',
        '>=' => 'GREATER_EQUAL',
        '<' => 'LESS',
        '<=' => 'LESS_EQUAL',
      }.freeze

      # Here are all the implemented Lox keywords (in uppercase)
      # These are enumerated in section 4.2.1 Token type
      @@keywords = %w[
        AND CLASS ELSE FALSE FUN FOR IF NIL OR
        PRINT RETURN SUPER THIS TRUE VAR WHILE
      ].map { |x| [x, x] }.to_h

      class ScanError < StandardError; end

      # Constructor. Initialize a tokenizer for Lox input.
      # @param source [String] Lox text to tokenize.
      def initialize(source = nil)
        @scanner = StringScanner.new('')
        start_with(source) if source
      end

      # Reset the tokenizer and make the given text, the current input.
      # @param source [String] Lox text to tokenize.
      def start_with(source)
        @scanner.string = source
        @lineno = 1
        @line_start = 0
      end

      # Scan the source and return an array of tokens.
      # @return [Array<Rley::Lexical::Token>] | Returns a sequence of tokens
      def tokens
        tok_sequence = []
        until @scanner.eos?
          token = _next_token
          tok_sequence << token unless token.nil?
        end
        tok_sequence << build_token('EOF', '')

        return tok_sequence
      end

      private

      def _next_token
        skip_intertoken_spaces
        curr_ch = scanner.peek(1)
        return nil if curr_ch.nil? || curr_ch.empty?

        token = nil

        if "(){},.;/*".include? curr_ch
          # Single delimiter or separator character
          token = build_token(@@lexeme2name[curr_ch], scanner.getch)
        elsif (lexeme = scanner.scan(/[+\-](?!\d)/))
          # Minus or plus character not preceding a digit
          token = build_token(@@lexeme2name[lexeme], lexeme)
        elsif (lexeme = scanner.scan(/[!=><]=?/))
          # One or two special character tokens
          token = build_token(@@lexeme2name[lexeme], lexeme)
        elsif (lexeme = scanner.scan(/-?\d+(?:\.\d+)?/))
          token = build_token('NUMBER', lexeme)
        elsif (lexeme = scanner.scan(/"(?:\\"|[^"])*"/))
          token = build_token('STRING', lexeme)
        elsif (lexeme = scanner.scan(/[a-zA-Z_][a-zA-Z_0-9]*/))
          keyw = @@keywords[lexeme.upcase]
          tok_type = keyw || 'IDENTIFIER'
          token = build_token(tok_type, lexeme)
        else # Unknown token
          erroneous = curr_ch.nil? ? '' : scanner.scan(/./)
          sequel = scanner.scan(/.{1,20}/)
          erroneous += sequel unless sequel.nil?
          raise ScanError, "Unknown token #{erroneous} on line #{lineno}"
        end

        return token
      end

      def build_token(aSymbolName, aLexeme)
        begin
          (value, symb) = convert_to(aLexeme, aSymbolName)
          col = scanner.pos - aLexeme.size - @line_start + 1
          pos = Rley::Lexical::Position.new(@lineno, col)
          if value
            token = Literal.new(value, aLexeme.dup, symb, pos)
          else
            token = Rley::Lexical::Token.new(aLexeme.dup, symb, pos)
          end
        rescue StandardError => e
          puts "Failing with '#{aSymbolName}' and '#{aLexeme}'"
          raise e
        end

        return token
      end

      def convert_to(aLexeme, aSymbolName)
        symb = aSymbolName
        case aSymbolName
          when 'FALSE'
            value = Datatype::False.instance
          when 'NIL'
            value = Datatype::Nil.instance            
          when 'NUMBER'
            value = Datatype::Number.new(aLexeme)
          when 'STRING'
            value = Datatype::LXString.new(aLexeme)
          when 'TRUE'
            value = Datatype::True.instance
          else
            value = nil
        end

        return [value, symb]
      end

      # Skip non-significant whitespaces and comments.
      # Advance the scanner until something significant is found.
      def skip_intertoken_spaces
        pre_pos = scanner.pos

        loop do
          ws_found = scanner.skip(/[ \t\f]+/) ? true : false
          nl_found = scanner.skip(/(?:\r\n)|\r|\n/)
          if nl_found
            ws_found = true
            next_line
          end
          cmt_found = false
          if scanner.scan(/\/(\/|\*)/)
            cmt_found = true
            case scanner.matched
              when '//'
                scanner.skip(/[^\r\n]*(?:(?:\r\n)|\r|\n)?/)
                next_line
              when '/*'
                skip_block_comment
                next
            end
          end
          break unless ws_found || cmt_found
        end

        curr_pos = scanner.pos
      end

      def skip_block_comment
        nesting_level = 1
        loop do
          comment_part = scanner.scan_until(/(?:\/\*)|(?:\*\/)|(?:(?:\r\n)|\r|\n)/)
          unless comment_part
            msg = "Unterminated '/* ... */' block comment on line #{lineno}"
            raise ScanError, msg
          end

          case scanner.matched
            when /(?:(?:\r\n)|\r|\n)/
              next_line
            when '*/'
              nesting_level -= 1
              break if nesting_level.zero?
            when '/*'
              nesting_level += 1
          end
        end
      end

      def next_line
        @lineno += 1
        @line_start = scanner.pos
      end
    end # class
  end # module
end # module
# End of file
