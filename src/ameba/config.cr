require "yaml"
require "./glob_utils"

# A configuration entry for `Ameba::Runner`.
#
# Config can be loaded from configuration YAML file and adjusted.
#
# ```
# config = Config.load
# config.formatter = my_formatter
# ```
#
# By default config loads `.ameba.yml` file in a current directory.
#
class Ameba::Config
  include GlobUtils

  AVAILABLE_FORMATTERS = {
    progress: Formatter::DotFormatter,
    todo:     Formatter::TODOFormatter,
    flycheck: Formatter::FlycheckFormatter,
    silent:   Formatter::BaseFormatter,
    disabled: Formatter::DisabledFormatter,
    json:     Formatter::JSONFormatter,
  }

  DEFAULT_PATHS = {
    "~/.ameba.yml",
    "~/.config/ameba/config.yml",
  }
  FILENAME     = ".ameba.yml"
  DEFAULT_PATH = Path[Dir.current] / FILENAME

  DEFAULT_GLOBS = %w(
    **/*.cr
    !lib
  )

  getter rules : Array(Rule::Base)
  property severity = Severity::Convention

  # Returns a list of paths (with wildcards) to files.
  # Represents a list of sources to be inspected.
  # If globs are not set, it will return default list of files.
  #
  # ```
  # config = Ameba::Config.load
  # config.globs = ["**/*.cr"]
  # config.globs
  # ```
  property globs : Array(String)

  # Represents a list of paths to exclude from globs.
  # Can have wildcards.
  #
  # ```
  # config = Ameba::Config.load
  # config.excluded = ["spec", "src/server/*.cr"]
  # ```
  property excluded : Array(String)

  # Returns `true` if correctable issues should be autocorrected.
  property? autocorrect = false

  @rule_groups : Hash(String, Array(Rule::Base))

  # Creates a new instance of `Ameba::Config` based on YAML parameters.
  #
  # `Config.load` uses this constructor to instantiate new config by YAML file.
  protected def initialize(config : YAML::Any)
    @rules = Rule.rules.map &.new(config).as(Rule::Base)
    @rule_groups = @rules.group_by &.group
    @excluded = load_array_section(config, "Excluded")
    @globs = load_array_section(config, "Globs", DEFAULT_GLOBS)

    return unless formatter_name = load_formatter_name(config)
    self.formatter = formatter_name
  end

  # Loads YAML configuration file by `path`.
  #
  # ```
  # config = Ameba::Config.load
  # ```
  def self.load(path = nil, colors = true)
    Colorize.enabled = colors
    content = read_config(path) || "{}"
    Config.new YAML.parse(content)
  rescue e
    raise "Config file is invalid: #{e.message}"
  end

  protected def self.read_config(path) : String?
    if path
      return File.exists?(path) ? File.read(path) : nil
    end
    path = Path[DEFAULT_PATH].expand(home: true)

    search_paths = path
      .parents
      .map! { |search_path| search_path / FILENAME }

    search_paths.reverse_each do |search_path|
      return File.read(search_path) if File.exists?(search_path)
    end

    DEFAULT_PATHS.each do |default_path|
      return File.read(default_path) if File.exists?(default_path)
    end
  end

  def self.formatter_names
    AVAILABLE_FORMATTERS.keys.join('|')
  end

  # Returns a list of sources matching globs and excluded sections.
  #
  # ```
  # config = Ameba::Config.load
  # config.sources # => list of default sources
  # config.globs = ["**/*.cr"]
  # config.excluded = ["spec"]
  # config.sources # => list of sources pointing to files found by the wildcards
  # ```
  def sources
    (find_files_by_globs(globs) - find_files_by_globs(excluded))
      .map { |path| Source.new File.read(path), path }
  end

  # Returns a formatter to be used while inspecting files.
  # If formatter is not set, it will return default formatter.
  #
  # ```
  # config = Ameba::Config.load
  # config.formatter = custom_formatter
  # config.formatter
  # ```
  property formatter : Formatter::BaseFormatter do
    Formatter::DotFormatter.new
  end

  # Sets formatter by name.
  #
  # ```
  # config = Ameba::Config.load
  # config.formatter = :progress
  # ```
  def formatter=(name : String | Symbol)
    unless formatter = AVAILABLE_FORMATTERS[name]?
      raise "Unknown formatter `#{name}`. Use one of #{Config.formatter_names}."
    end
    @formatter = formatter.new
  end

  # Updates rule properties.
  #
  # ```
  # config = Ameba::Config.load
  # config.update_rule "MyRuleName", enabled: false
  # ```
  def update_rule(name, enabled = true, excluded = nil)
    rule = @rules.find(&.name.==(name))
    raise ArgumentError.new("Rule `#{name}` does not exist") unless rule

    rule
      .tap(&.enabled = enabled)
      .tap(&.excluded = excluded)
  end

  # Updates rules properties.
  #
  # ```
  # config = Ameba::Config.load
  # config.update_rules %w(Rule1 Rule2), enabled: true
  # ```
  #
  # also it allows to update groups of rules:
  #
  # ```
  # config.update_rules %w(Group1 Group2), enabled: true
  # ```
  def update_rules(names, enabled = true, excluded = nil)
    names.try &.each do |name|
      if rules = @rule_groups[name]?
        rules.each do |rule|
          rule.enabled = enabled
          rule.excluded = excluded
        end
      else
        update_rule name, enabled, excluded
      end
    end
  end

  private def load_formatter_name(config)
    name = config["Formatter"]?.try &.["Name"]?
    name.try(&.to_s)
  end

  private def load_array_section(config, section_name, default = [] of String)
    case value = config[section_name]?
    when .nil?  then default
    when .as_s? then [value.to_s]
    when .as_a? then value.as_a.map(&.as_s)
    else
      raise "Incorrect '#{section_name}' section in a config files"
    end
  end

  # :nodoc:
  module RuleConfig
    macro properties(&block)
      {% definitions = [] of NamedTuple %}
      {% if block.body.is_a? Assign %}
        {% definitions << {var: block.body.target, value: block.body.value} %}
      {% elsif block.body.is_a? Call %}
          {% definitions << {var: block.body.name, value: block.body.args.first} %}
      {% elsif block.body.is_a? TypeDeclaration %}
        {% definitions << {var: block.body.var, value: block.body.value, type: block.body.type} %}
      {% elsif block.body.is_a? Expressions %}
        {% for prop in block.body.expressions %}
          {% if prop.is_a? Assign %}
            {% definitions << {var: prop.target, value: prop.value} %}
          {% elsif prop.is_a? Call %}
            {% definitions << {var: prop.name, value: prop.args.first} %}
          {% elsif prop.is_a? TypeDeclaration %}
            {% definitions << {var: prop.var, value: prop.value, type: prop.type} %}
          {% end %}
        {% end %}
      {% end %}

      {% properties = {} of MacroId => NamedTuple %}
      {% for df in definitions %}
        {% name = df[:var].id %}
        {% key = name.camelcase.stringify %}
        {% value = df[:value] %}
        {% type = df[:type] %}
        {% converter = nil %}

        {% if key == "Severity" %}
          {% type = Severity %}
          {% converter = SeverityYamlConverter %}
        {% end %}

        {% if type == nil %}
          {% if value.is_a? BoolLiteral %}
            {% type = Bool %}
          {% elsif value.is_a? StringLiteral %}
            {% type = String %}
          {% elsif value.is_a? NumberLiteral %}
            {% if value.kind == :i32 %}
              {% type = Int32 %}
            {% elsif value.kind == :i64 %}
              {% type = Int64 %}
            {% elsif value.kind == :f32 %}
              {% type = Float32 %}
            {% elsif value.kind == :f64 %}
              {% type = Float64 %}
            {% end %}
          {% end %}

          {% type = Nil if type == nil %}
        {% end %}

        {% properties[name] = {key: key, default: value, type: type, converter: converter} %}

        @[YAML::Field(key: {{ key }}, converter: {{ converter }}, type: {{ type }})]
        {% if type == Bool %}
          property? {{ name }} : {{ type }} = {{ value }}
        {% else %}
          property {{ name }} : {{ type }} = {{ value }}
        {% end %}
      {% end %}

      {% unless properties["enabled".id] %}
        @[YAML::Field(key: "Enabled")]
        property? enabled = true
      {% end %}

      {% unless properties["severity".id] %}
        @[YAML::Field(key: "Severity", converter: Ameba::SeverityYamlConverter)]
        property severity = {{ @type }}.default_severity
      {% end %}

      {% unless properties["excluded".id] %}
        @[YAML::Field(key: "Excluded")]
        property excluded : Array(String)?
      {% end %}
    end

    macro included
      GROUP_SEVERITY = {
        Lint:        Ameba::Severity::Warning,
        Metrics:     Ameba::Severity::Warning,
        Performance: Ameba::Severity::Warning,
      }

      class_getter default_severity : Ameba::Severity do
        GROUP_SEVERITY[group_name]? || Ameba::Severity::Convention
      end

      macro inherited
        include YAML::Serializable
        include YAML::Serializable::Strict

        def self.new(config = nil)
          if (raw = config.try &.raw).is_a?(Hash)
            yaml = raw[rule_name]?.try &.to_yaml
          end
          from_yaml yaml || "{}"
        end
      end
    end
  end
end
