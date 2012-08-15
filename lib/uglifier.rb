# encoding: UTF-8

require "execjs"
require "multi_json"

class Uglifier
  Error = ExecJS::Error
  # MultiJson.engine = :json_gem

  # Default options for compilation
  DEFAULTS = {
    :mangle => true, # Mangle variable and function names, use :vars to skip function mangling
    :toplevel => false, # Mangle top-level variable names
    :except => ["$super"], # Variable names to be excluded from mangling
    :max_line_length => 32 * 1024, # Maximum line length
    :squeeze => true, # Squeeze code resulting in smaller, but less-readable code
    :seqs => true, # Reduce consecutive statements in blocks into single statement
    :dead_code => true, # Remove dead code (e.g. after return)
    :no_console => false, # Remove console method calls.
    :lift_vars => false, # Lift all var declarations at the start of the scope
    :unsafe => false, # Optimizations known to be unsafe in some situations
    :copyright => true, # Show copyright message
    :ascii_only => false, # Encode non-ASCII characters as Unicode code points
    :inline_script => false, # Escape </script
    :quote_keys => false, # Quote keys in object literals
    :beautify => false, # Ouput indented code
    :beautify_options => {
      :indent_level => 4,
      :indent_start => 0,
      :space_colon => false
    }
  }

  SourcePath = File.expand_path("../uglify.js", __FILE__)
  ES5FallbackPath = File.expand_path("../es5.js", __FILE__)

  # Minifies JavaScript code using implicit context.
  #
  # source should be a String or IO object containing valid JavaScript.
  # options contain optional overrides to Uglifier::DEFAULTS
  #
  # Returns minified code as String
  def self.compile(source, options = {})
    self.new(options).compile(source)
  end

  # Initialize new context for Uglifier with given options
  #
  # options - Hash of options to override Uglifier::DEFAULTS
  def initialize(options = {})
    @options = DEFAULTS.merge(options)
    @context = ExecJS.compile(File.open(ES5FallbackPath, "r:UTF-8").read + File.open(SourcePath, "r:UTF-8").read)
  end

  # Minifies JavaScript code
  #
  # source should be a String or IO object containing valid JavaScript.
  #
  # Returns minified code as String
  def compile(source)
    source = source.respond_to?(:read) ? source.read : source.to_s

    js = []
    js << "var result = '';"
    js << "var source = #{MultiJson.encode(source)};"
    js << "var ast = UglifyJS.parser.parse(source);"

    if @options[:lift_vars]
      js << "ast = UglifyJS.uglify.ast_lift_variables(ast);"
    end

    if @options[:copyright]
      js << <<-JS
      var comments = UglifyJS.parser.tokenizer(source)().comments_before;
      for (var i = 0; i < comments.length; i++) {
        var c = comments[i];
        result += (c.type == "comment1") ? "//"+c.value+"\\n" : "/*"+c.value+"*/\\n";
      }
      JS
    end

    if @options[:no_console]
      js << <<-JS
      var ast_squeeze_console = function(ast) {
              var w = UglifyJS.uglify.ast_walker(), walk = w.walk, scope;
               return w.with_walkers({
                      "stat": function(stmt) {
                              if(stmt[0] === "call" && stmt[1][0] == "dot" && stmt[1][1] instanceof Array && stmt[1][1][0] == 'name' && stmt[1][1][1] == "console") {
                                      return ["block"];
                              }
                              return ["stat", walk(stmt)];
                      },
                      "call": function(expr, args) {
                              if (expr[0] == "dot" && expr[1] instanceof Array && expr[1][0] == 'name' && expr[1][1] == "console") {
                                      return ["atom", "0"];
                              }
                      }
              }, function() {
                      return walk(ast);
              });
      };
      ast = ast_squeeze_console(ast);
      JS
    end
    
    if @options[:mangle]
      js << "ast = UglifyJS.uglify.ast_mangle(ast, #{MultiJson.encode(mangle_options)});"
    end

    if @options[:squeeze]
      js << "ast = UglifyJS.uglify.ast_squeeze(ast, #{MultiJson.encode(squeeze_options)});"
    end

    if @options[:unsafe]
      js << "ast = UglifyJS.uglify.ast_squeeze_more(ast);"
    end

    js << "result += UglifyJS.uglify.gen_code(ast, #{MultiJson.encode(gen_code_options)});"

    if !@options[:beautify] && @options[:max_line_length]
      js << "result = UglifyJS.uglify.split_lines(result, #{@options[:max_line_length].to_i})"
    end

    js << "return result + ';';"

    @context.exec js.join("\n")
  end
  alias_method :compress, :compile

  private

  def mangle_options
    {
      "toplevel" => @options[:toplevel],
      "defines" => {},
      "except" => @options[:except],
      "no_functions" => @options[:mangle] == :vars
    }
  end

  def squeeze_options
    {
      "make_seqs" => @options[:seqs],
      "dead_code" => @options[:dead_code],
      "keep_comps" => !@options[:unsafe]
    }
  end

  def gen_code_options
    options = {
      :ascii_only => @options[:ascii_only],
      :inline_script => @options[:inline_script],
      :quote_keys => @options[:quote_keys]
    }

    if @options[:beautify]
      options.merge(:beautify => true).merge(@options[:beautify_options])
    else
      options
    end
  end
end
