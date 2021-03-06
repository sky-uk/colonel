require 'spec_helper'
require 'pry'
require 'fileutils'
require 'elasticsearch'

require 'support/sample_content'

describe "Stress test", live: true do
  before do
    Colonel.config.storage_path = 'tmp/integration_test'

    ContentItem.ensure_index!
    ContentItem.put_mapping!
  end

  after do
    FileUtils.rm_rf('tmp/integration_test')
  end

  let :time do
    Time.now
  end

  it "should dump and restore 20 documents without complex history" do
    doc_ids = []
    docs = (1..20).to_a.map do |i|
      info = {
        title: TITLES.sample(1).first,
        tags: TAGS.sample(5),
        slug: "#{SLUGS.sample(1).first}_#{i}",
        abstract: CONTENT.sample(1).first,
        body: CONTENT.sample(4).flatten.join("\n\n")
      }

      doc = ContentItem.new(info)
      doc.save!({name: "John Doe", email: "john@example.com"}, "Commit message", time)
      doc_ids << doc.id

      doc.body += CONTENT.sample(1).first
      doc.save!({name: "John Doe", email: "john@example.com"}, "Commit message", time + 1)

      doc.tags += TAGS.sample(2)
      doc.save!({name: "John Doe", email: "john@example.com"}, "Commit message", time + 2)

      doc
    end

    docs.sample(15).each do |doc|
      doc.promote!('master', 'published', {name: "John Doe", email: "john@example.com"}, "Published!", time + 5)
    end

    docs.sample(5).each do |doc|
      doc.promote!('master', 'archived', {name: "John Doe", email: "john@example.com"}, "Archived!", time + 10)
      doc.save_in!('archived', {name: "John Doe", email: "john@example.com"}, "Commit message", time + 12)
    end

    dump = StringIO.new

    index = DocumentIndex.new('tmp/integration_test')

    docs = index.documents.map { |doc| Document.open(doc[:name]) }
    Serializer.generate(docs, dump)

    FileUtils.rm_rf('tmp/integration_test')

    client = ::Elasticsearch::Client.new(host: Colonel.config.elasticsearch_uri, log: false)
    client.indices.delete index: Colonel.config.index_name

    dump.rewind

    ContentItem.scope 'visible', on: ['save', 'promotion'], to: ['published', 'archived']

    Serializer.load(dump) do |doc|
      expect(doc.history.length).to be >= 3
    end

    expect(index.documents.length).to eq(20)
    expect(index.documents.map { |d| d[:name] }.sort).to eq(doc_ids.sort)

    documents = index.documents.map { |d| Document.open(d[:name]) }
    Indexer.index(documents, {'content_item' => ContentItem})

    client.indices.refresh index: Colonel.config.index_name

    expect(ContentItem.list[:total]).to eq(20)
    expect(ContentItem.list(state: 'published')[:total]).to eq(15)

    currently_published = ContentItem.search('state:published', scope: 'visible')[:total]
    expect(currently_published).to be >= 10
    expect(currently_published).to be <= 15
  end
end
