require 'pry'
require 'puppet/managedmac/common'

Puppet::Type.newtype(:mobileconfig) do
  
  ensurable
  
  newparam(:name) do
    isnamevar
  end
  
  newproperty(:content, :array_matching => :all) do
    desc "Array of Hashes containing the payload data for the profile. 
    Each hash is a key/value store represnting the payload settings
    a given PayloadType.
    
    * This content can be complicated to construct manually.
    * Required Keys: PayloadIdentifier, PayloadType
    * You should always include a unique PayloadIdentifier key/value
      for each Hash in the Array.
    * You should always include an appropriate PayloadType key/value
      for each Hash in the Array.
    * Other Payload keys (PayloadDescription, etc.) will be ignored.
    
    Corresponds to PayloadContent."
    
    def is_to_s(value)
      value.hash
    end
    
    def should_to_s(value)
      value.hash
    end
    
    # Make sure that each of the Hashes in the Array contains some critical keys
    #
    # - PayloadIdentifier: our primary key for doing joins in equality tests.
    # We need this for matching up _is_ and _should_ values.
    #
    # - PayloadType: required by OS X so that it knows which preference domain
    # is being managed in the profile; we do not validate the string, just it's 
    # presence. If you fail to provide a valid domain, profile installation
    # will fail outright.
    #
    validate do |value|
      required_keys = ['PayloadIdentifier', 'PayloadType']
      required_keys.each do |key|
        unless value.key?(key)
          raise ArgumentError, "Missing #{key} key! #{value.pretty_inspect}"
        end
      end
    end
    
    # Normalize the :content array
    munge do |value|
      ::ManagedMacCommon::destringify value
    end
    
  end
  
  newproperty(:description) do
    desc "String that describes what this profile does.
      Corresponds to PayloadDescription."
    validate do |value|
      unless value.is_a? String
        raise ArgumentError, "Expected String, got #{value.class}"
      end
    end
    defaultto 'Installed by Puppet'
  end
  
  newproperty(:displayname) do
    desc "String displayed as the title common name for this profile.
      Corresponds to PayloadDisplayName."
    validate do |value|
      unless value.is_a? String
        raise ArgumentError, "Expected String, got #{value.class}"
      end
    end
    defaultto { "Puppet Mobile Config: " + @resource[:name] }
  end
  
  newproperty(:organization) do
    desc "String that describes the org that prodcued the profile.
      Corresponds to PayloadOrganization."
    validate do |value|
      unless value.is_a? String
        raise ArgumentError, "Expected String, got #{value.class}"
      end
    end
    defaultto 'Puppet Labs'
  end
  
  newproperty(:removaldisallowed) do
    desc "Bool: whether or not to allow the removal of the profile. 
      Setting this to false means it can be removed. Don't blame me
      for the stupid name, blame Apple.
      Corresponds to PayloadRemovalDisallowed."
    newvalues(:true, :false)
    defaultto :false
  end
  
end
