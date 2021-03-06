require 'rugged'
require 'elasticsearch'
require 'colonel/version'

require 'colonel/document'
require 'colonel/document/document_type'

require 'colonel/document/content'

require 'colonel/document/revision'
require 'colonel/document/revision_collection'

require 'colonel/document_index'

require 'colonel/search/elasticsearch_provider'
require 'colonel/search/elasticsearch_result_set'

require 'colonel/serializer'
require 'colonel/indexer'

module Colonel
  # Public: Sets configuration options.
  #
  # Colonel.config.storage_path               - location to store git repo on disk
  # Colonel.config.index_name                 - the name of elasticsearch index to store into
  # Colonel.config.elasticsearch_uri          - host for elasticsearch
  # Colonel.config.rugged_backend             - storage backend, an instance of Rugged::Backend
  # Colonel.config.elasticsearch_timeout_secs - request timeout for elasticsearch
  #
  # Returns a config struct
  def self.config
    defaults = {
      :storage_path => 'storage',
      :index_name => 'colonel-storage',
      :elasticsearch_uri => 'localhost:9200',
      :rugged_backend => nil,
      :elasticsearch_timeout_secs => 60
    }

    ordered_struct_fields = defaults.keys
    ordered_struct_values = ordered_struct_fields.map{|k| defaults[k]}

    @config ||= Struct.new(*ordered_struct_fields).new(*ordered_struct_values)
  end
end
