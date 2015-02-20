require 'pry'
require 'cfpropertylist'
require 'puppet/managedmac/common'

Puppet::Type.type(:dsconfigad).provide(:default) do

  defaultfor :operatingsystem  => :darwin
  commands   :dsconfigad       => '/usr/sbin/dsconfigad'

  mk_resource_methods

  DSCONFIGAD_KEY_MAP = {
    :fqdn           =>  'Active Directory Domain',
    :computer       =>  'Computer Account',
    :mobile         =>  'Create mobile account at login',
    :mobileconfirm  =>  'Require confirmation',
    :localhome      =>  'Force home to startup disk',
    :useuncpath     =>  'Use Windows UNC path for home',
    :protocol       =>  'Network protocol',
    :shell          =>  'Shell',
    :uid            =>  'UID Mapping',
    :gid            =>  'User GID Mapping',
    :ggid           =>  'Group GID Mapping',
    :authority      =>  'Generate Kerberos authority',
    :preferred      =>  'Preferred Domain controller',
    :groups         =>  'Allowed admin groups',
    :alldomains     =>  'Authentication from any domain',
    :packetsign     =>  'Packet signing',
    :packetencrypt  =>  'Packet encryption',
    :namespace      =>  'Namespace mode',
    :passinterval   =>  'Password change interval',
    :restrictddns   =>  'Restrict Dynamic DNS updates',
  }

  PROPERTIES = [
    :mobile=,
    :mobileconfirm=,
    :localhome=,
    :useuncpath=,
    :protocol=,
    :sharepoint=,
    :shell=,
    :shell=,
    :preferred=,
    :alldomains=,
    :packetsign=,
    :packetencrypt=,
  ]

  NO_FLAG_PROPERTIES = [
    :uid=,
    :gid=,
    :ggid=,
    :groups=,
    :preferred=,
  ]

  # Override the setter methods generated by mk_resource_methods so we can
  # build them into CLI arguments using the #flag_setter method
  [PROPERTIES, NO_FLAG_PROPERTIES].each_with_index do |array, i|
    array.each do |m|
      define_method(m) do |value|
        args = [m, value]
        args << true if i != 0
        flag_setter *args
      end
    end
  end

  class << self

    include ManagedMacCommon

    def instances
      config = new(get_resource_properties)
      instances = []
      unless config.ensure == :absent
        instances << config
      end
      instances
    end

    # Puppet MAGIC
    def prefetch(resources)
      instances.each do |prov|
        if resource = resources[prov.name]
          resource.provider = prov
        end
      end
    end

    def get_resource_properties
      config = get_active_directory_configuration
      return {} if nil_or_empty?(config)
      transform_config config
    end

    def transform_config(config)
      config = DSCONFIGAD_KEY_MAP.inject({}) do |memo,(k,v)|
        memo[k] = convert_boolean config[v]
        memo
      end
      config[:computer].chop if config[:computer]
      config[:ensure] = :present
      config[:name]   = config.delete :fqdn
      config
    end

    def convert_boolean(value)
      case value
      when TrueClass
        :enable
      when FalseClass
        :disable
      else
        value
      end
    end

    def get_active_directory_configuration
      dict = dsconfigad('-show', '-xml')
      flatten_config read_plist_from_string(dict)
    end

    def flatten_config(config)
      config.inject({}) { |memo,(k,v)| memo.merge! v; memo }
    end

    def read_plist_from_string(string)
      unless nil_or_empty? string
        plist = CFPropertyList::List.new(:data => string)
        return CFPropertyList.native_types(plist.value)
      end
      return {}
    end

  end

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def create
    @property_flush[:ensure] = :present
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  # This links up with the crazy define_method routines to create
  # setters that build CLI arguments
  def flag_setter(setter, value, accepts_no_flag=false)
    flag = setter.to_s.chop
    args = if self.class.nil_or_empty?(value) and accepts_no_flag
      ["-no#{flag}"]
    else
      ["-#{flag}", %Q{"#{value}"}]
    end
    (@configuration_flags ||= []) << args
  end

  def groups=(value)
    flag_setter(:groups=, value.join(','), true)
  end

  def restrictddns=(value)
    flag_setter(:restrictDDNS=, value.join(','))
  end

  def specify_ou_path?
    !(resource[:ou].nil? || resource[:ou].empty?)
  end

  def build_args(required)
    Hash[required.map { |k| [k, resource[k]] }]
  end

  def validate_bind_value(key, value)
    if value.nil? or value.empty? or value == :absent
      raise Puppet::Error,
        "Missing required parameter: #{key} is invalid or empty"
    end
    value
  end

  def transform_bind_key(key)
    key == :name ? '-add' : "-#{key}"
  end

  def normalize_bind_args(params_hash)
    params_hash.inject([]) do |memo,(k,v)|
      memo << [transform_bind_key(k), validate_bind_value(k,v)]
      memo
    end
  end

  def force_bind?
    resource[:force] == :enable
  end
  alias_method :force_unbind?, :force_bind?

  def leave_domain?
    resource[:leave] == :enable
  end

  def check_credentials(credentials)
    Hash[*credentials].each { |k,v| validate_bind_value k, v }
    credentials
  end

  def bind
    notice("Binding to domain...")
    required = [:name, :computer, :username, :password]
    required << :ou if specify_ou_path?
    args = normalize_bind_args(build_args(required)).flatten
    args << '-force' if force_bind?
    dsconfigad args
  end

  def unbind
    notice("Unbinding from domain...")
    args = if leave_domain?
      ['-leave']
    else
      args = build_args([:username, :password])
      args = ['-remove'] + normalize_bind_args(args).flatten
      args << '-force' if force_unbind?
      args
    end
    dsconfigad args
  end

  def configure
    notice("Configuring plugin...")
    binding.pry
    dsconfigad (@configuration_flags || build_configuration_options).flatten!
  end

  def build_configuration_options
    properties = Puppet::Type::Dsconfigad.properties.map(&:name)
    resource.to_hash.each do |k,v|
      self.send("#{k}=", v) if properties.member? k
    end
  end

  def already_bound?
    !computer == :absent
  end

  def flush
    if @property_flush[:ensure] == :absent
      unbind
    else
      bind unless already_bound?
      # configure if already_bound?
    end
    binding.pry
    @property_hash = self.class.get_resource_properties
  end

end
