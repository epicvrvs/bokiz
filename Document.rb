require 'fileutils'
require 'htmlentities'

require 'nil/file'
require 'nil/string'

require_relative 'functions'

class Document
  attr_reader :outputDirectory
  attr_accessor :sections

  def initialize(path, outputDirectory)
    initialiseFunctions
    @nodes = loadDocument(path)
    @html = HTMLEntities.new
    @outputDirectory = outputDirectory
  end

  def loadDocument(path)
    @basename = getBasename(path)
    @markup = Nil.readFile(path)
    raise 'Unable to open file' if @markup == nil
    @offset = 0
    @lastLine = nil
    @line = 1
    @sections = []
    return parseDocument
  end

  def getBasename(path)
    filename = File.basename(path)
    match = filename.match(/(.+?)\.bokiz/)
    if match == nil
      raise "The file must use the bokiz extension - #{filename.inspect} is invalid"
    end
    return match[1]
  end

  def initialiseFunctions
    @functions = {
      'bold' => BoldText,
      'section' => SectionFunction,
      'subsection' => SubsectionFunction,
      'subsubsection' => SubsubsectionFunction,
      'paragraph' => Paragraph,
      'list' => List,
      'element' => Element,
      'monospace' => Monospace,
      'table' => Table,
      'row' => Row,
      'column' => Column,
      'group' => Group,
      'code' => Code,
      'math' => LaTeXMath,
      'center-math' => CenteredLaTeXMath,
      'link' => Link,
      'enumeration' => Enumeration,
    }
  end

  def error(message)
    raise "Error on line #{@line}: #{message}"
  end

  def getInput
    return @markup[@offset]
  end

  def parseDocument(isCode = false)
    contents = []
    currentString = ''
    while @offset < @markup.size
      input = getInput
      if @lastLine != @line
        @lastLine = @line
        #puts "#{@line} #{@markup[@offset, 20].inspect}"
      end
      addString = lambda { currentString += input }
      case input
      when '['
        if isCode
          addString.call
          advance
          next
        end
        if !currentString.empty?
          contents << currentString
          currentString = ''
        end
        string = @markup[@offset..-1]
        noArgumentsPattern = /\A\[([a-z\-]+?)[ \n]/
        argumentsPattern = /\A\[([a-z\-]+?)\[(.+?)\][ \n]/
        arguments = nil
        match = string.match(noArgumentsPattern)
        if match == nil
          match = string.match(argumentsPattern)
          if match == nil
            error 'Unable to parse the name of a function'
          end
          arguments = match[2]
        end
        name = match[1]
        fullMatch = match[0]
        @offset += fullMatch.size
        if fullMatch.index("\n") != nil
          @line += 1
        end
        functionClass = @functions[name]
        if functionClass == nil
          error "Invalid node name: #{name}"
        end
        node = functionClass.new(self, arguments)
        node.children = parseDocument(node.isCode)
        contents << node if node.printable
        next
      when ']'
        if isCode && @markup[@offset - 1] != "\n"
          #encountered a non-terminal end of scope tag within a code segment
          #treat it like a regular string and continue parsing
          addString.call
          advance
          next
        end
        advance
        break
      when "\n"
        @line += 1
        addString.call
      when '@'
        #escape sequence so one can print []@ without messing up the parsing the process
        advance
        currentString += getInput
      else
        addString.call
      end
      advance
    end
    if !currentString.empty?
      contents << currentString
    end
    return contents
  end

  def advance
    @offset += 1
  end

  def fixWhitespace(input)
    space = '&nbsp;'
    if input == ' '
      output = space
    else
      output = input.gsub('  ', space + ' ')
    end
    return output
  end

  def escapeString(string, type)
    case type
    when :html
      output = @html.encode(string)
      output = fixWhitespace(output)
      return output
    when :latex
      targets = "\\_&^|{}"
      targets.each_char do |char|
        string = string.gsub(char) { "\\#{char}" }
      end
      return string
    else
      raise "Invalid type: #{type}"
    end
  end

  def generateSpecificOutput(path, type, latexHeader = nil)
    output = latexHeader == nil ? '' : latexHeader
    @sections = []
    @nodes.each do |node|
      if node.class == String
        output += escapeString(node, type)
      else
        output += node.method(type).call
      end
    end
    if type == :html && !@sections.empty?
      output = "<div class=\"overview\">\n#{getIndexMarkup}</div>\n\n#{output}"
    end
    Nil.writeFile(path, output)
  end

  def getIndexMarkup(sections = @sections, numericIdentifier = [])
    counter = 1
    output = "<ul>\n"
    sections.each do |section|
      currentIdentifiers = numericIdentifier + [counter]
      if currentIdentifiers.size == 1
        number = currentIdentifiers.first.to_s + '.'
      else
        number = currentIdentifiers.map { |x| x.to_s }.join('.')
      end
      output += "<li><a href=\"\##{section.id}\">#{number} #{section.name}</a></li>\n"
      children = section.children
      if !children.empty?
        output += "<li>\n#{getIndexMarkup(children, currentIdentifiers)}</li>\n"
      end
      counter += 1
    end
    output += "</ul>\n"
    return output
  end

  def generateOutput(latexHeaderPath)
    directory = @outputDirectory
    htmlPath = Nil.joinPaths(directory, "#{@basename}.html")
    generateSpecificOutput(htmlPath, :html)
    temporaryDirectory = Nil.joinPaths(directory, 'temporary')
    FileUtils.mkdir_p(temporaryDirectory)
    latexPath = Nil.joinPaths(temporaryDirectory, "#{@basename}.tex")
    latexHeader = Nil.readFile(latexHeaderPath)
    if latexHeader == nil
      raise "Unable to read the LaTeX header file from #{latexHeaderPath}"
    end
    generateSpecificOutput(latexPath, :latex, latexHeader)
    FileUtils.rm_rf(temporaryDirectory)
  end
end
