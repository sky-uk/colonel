require 'spec_helper'

describe Document do
  let(:root_oid) { 'root-oid' }

  let(:root_ref) do
    double(:root_ref).tap do |root_ref|
      allow(root_ref).to receive(:target_id).and_return(root_oid)
    end
  end

  let(:root_commit) do
    double(:root_commit,
      oid: root_oid,
      message: 'First Commit',
      author: {},
      time: time,
      parents: [])
  end

  before(:all) do
    Colonel::DocumentType.new('document') do
      search_provider_class :none # turn off search
    end
  end

  describe "creation" do
    before do
      allow(Rugged::Repository).to receive(:new).and_return nil
    end

    it "should create a document" do
      expect(Document.new(nil)).to be_a Document
    end

    it "should have a random name" do
      document = Document.new(nil)
      expect(document.id).to match /^[0-9a-f]{32}$/
    end

    it "should have a content if specified" do
      document = Document.new({content: 'my test content'})
      expect(document.content.content).to eq 'my test content'
    end
  end

  describe "git storage" do
    it "should create a repository with the document's name when asked for repo" do
      doc = Document.new(nil)
      expect(Rugged::Repository).to receive(:init_at).with("storage/#{doc.id}", :bare)

      doc.repository
    end
  end

  describe "alternative storage" do
    let :doc do
      double(:document).tap do |it|
        allow(it).to receive(:id).and_return("foo")
      end
    end

    before :each do
      Colonel.config.rugged_backend = :foo
    end

    after :each do
      Colonel.config.rugged_backend = nil
    end

    let :index do
      double(:index).tap do |index|
        allow(index).to receive(:lookup).with("test").and_return({name: "test", type: "test-type"})
      end
    end

    it "should init with a given backend" do
      doc = Document.new(nil)
      expect(Rugged::Repository).to receive(:init_at).with("storage/#{doc.id}", :bare, backend: :foo)

      doc.repository
    end

    it "should open with a given backend" do
      allow(Document).to receive(:new).and_return(doc)
      allow(doc).to receive(:load!)
      allow(Document).to receive(:index).and_return(index)

      expect(Rugged::Repository).to receive(:bare).with("storage/test-id", backend: :foo)

      Document.open("test-id")
    end
  end

  describe "saving to storage" do
    let :document do
      Document.new(nil).tap do |it|
        allow(it).to receive(:repository).and_return(repository)
        allow(it).to receive(:revisions).and_return(double(:revisions))
      end
    end

    let :repository do
      double(:repository).tap do |it|
        allow(it).to receive(:references).and_return(double(:references))
      end
    end

    let :time do
      Time.now
    end

    let :revision do
      double(:revision).tap do |it|
        allow(it).to receive(:write!)
      end
    end

    let :previous_revision do
      double(:previous_revision)
    end

    let :head_ref do
      double(:head_ref)
    end

    let :root_ref do
      double(:root_ref).tap do |it|
        allow(it).to receive(:target_id).and_return("root_id")
      end
    end

    let :root_revision do
      double(:root_revision).tap do |it|
        allow(it).to receive(:id).and_return("root_id")
        allow(it).to receive(:write!)
      end
    end

    it 'should create a tagged root revision' do
      allow(document.revisions).to receive(:root_revision).and_return(nil)
      allow(document.revisions).to receive(:[]).with('master').and_return(nil)

      allow(Revision).to receive(:new).and_return(revision)

      the_colonel = { name: 'The Colonel', email: 'colonel@example.com' }

      expect(Revision).to receive(:new).with(document, "", the_colonel, "First Commit", time, nil).and_return(root_revision)
      expect(root_revision).to receive(:write!).and_return("foo")
      expect(repository.references).to receive(:create).with('refs/tags/root', "foo")

      document.save!({ name: 'The Colonel', email: 'colonel@example.com' }, 'Second Commit', time)
    end

    it "should create a commit on first save" do
      allow(document.revisions).to receive(:root_revision).and_return(root_revision)
      allow(document.revisions).to receive(:[]).with('master').and_return(nil)

      allow(revision).to receive(:write!)

      expect(Revision).to receive(:new).with(document, document.content, :author, "", time, root_revision).and_return(revision)

      rev = document.save!(:author, "", time)

      expect(rev).to eq(revision)
    end

    it "should add a commit on subsequent saves" do
      allow(document.revisions).to receive(:root_revision).and_return(root_revision)
      allow(document.revisions).to receive(:[]).with('master').and_return(previous_revision)
      allow(document).to receive(:init_repository).with(repository, time)

      allow(revision).to receive(:write!)

      expect(Revision).to receive(:new).with(document, document.content, :author, "", time, previous_revision).and_return(revision)

      rev = document.save!(:author, "", time)

      expect(rev).to eq(revision)
    end
  end

  describe "registering with index" do
    let :repo do
      Struct.new(:references).new(
        double(:references).tap do |refs|
          allow(refs).to receive(:[]).with("refs/heads/master").and_return(head)
        end
      )
    end

    let :index do
      double(:index)
    end

    let :head do
      Struct.new(:target_id).new('head')
    end

    let :document do
      Document.new(content: "some content")
    end

    let :time do
      Time.now
    end

    let :mock_index do
      index = Object.new
      allow(index).to receive(:register).with(document.id, document.type).and_return(true)
    end

    let :revisions do
      double(:revisions)
    end

    before do
      allow(document).to receive(:repository).and_return(repo)
      allow(document).to receive(:revisions).and_return(revisions)
    end

    it "shoud have a document index" do
      expect(document.index).to be_a(DocumentIndex)
      expect(document.index.storage_path).to eq(Colonel.config.storage_path)
    end

    it "should register with document index when saving" do
      revision = double(:revision)

      allow(document).to receive(:init_repository).and_return(true)
      allow(revisions).to receive(:[]).with('master').and_return(true)
      allow(Revision).to receive(:new).and_return(revision)
      allow(revision).to receive(:write!)

      expect(document.index).to receive(:register).with(document.id, document.type.type).and_return(true)

      rev = document.save!({ email: 'colonel@example.com', name: 'The Colonel' }, 'save from the colonel', time)
      expect(rev).to eq(revision)
    end
  end

  describe "loading from storage" do
    let :repo do
      double(:repo).tap do |it|
        allow(it).to receive(:references).and_return(double(:references))
      end
    end

    let :index do
      double(:index).tap do |index|
        allow(index).to receive(:lookup).with("test").and_return({type: "test-type", name: "test"})
      end
    end

    let :revision do
      double(:revision)
    end

    let :document do
      Document.new(nil, repo: repo).tap do |it|
        allow(it).to receive(:revisions).and_return(double(:revisions))
      end
    end

    it "should open the repository and get content for master" do
      expect(Rugged::Repository).to receive(:bare).with("storage/test").and_return(repo)
      expect(Document).to receive(:new).with(nil, {id: 'test', repo: repo, type: DocumentType.get('document')}).and_return(document)
      expect(document.revisions).to receive(:[]).with('master').and_return(revision)
      expect(revision).to receive(:content).and_return(Content.new({content: 'foo'}))

      doc = Document.open("test")

      expect(doc).to be_a(Document)
      expect(doc.content.content).to eq('foo')
    end
  end

  describe "states" do
    let :repo do
      Struct.new(:references).new(Object.new)
    end

    let :index do
      Object.new
    end

    let :document do
      Document.new({content: "some content"}, repo: repo).tap do |it|
        allow(it).to receive(:revisions).and_return(double(:revisions))
      end
    end

    let :content do
      Content.new(foo: "bar")
    end

    let :author do
      {name: 'Test', email: 'test@example.com'}
    end

    let :time do
      Time.now
    end

    describe "promoting" do
      it "promotes to a new state" do
        new_revision = double(:revision)
        master_rev = double(:master_revision).tap { |it| allow(it).to receive(:content).and_return(content) }
        root_rev = double(:root_revision)

        allow(document.revisions).to receive(:[]).with("master").and_return(master_rev)
        allow(document.revisions).to receive(:[]).with("published").and_return(nil)
        allow(document.revisions).to receive(:root_revision).and_return(root_rev)

        expect(Revision).to receive(:new).with(document, master_rev.content, author, "", time, root_rev, master_rev).and_return(new_revision)
        expect(new_revision).to receive(:write!).with(document.repository, "refs/heads/published")

        revision = document.promote!('master', 'published', author, "", time)
      end

      it "promotes to an existing state" do
        new_revision = double(:revision)
        master_rev = double(:master_revision).tap { |it| allow(it).to receive(:content).and_return(content) }
        published_rev = double(:published_revision)

        allow(document.revisions).to receive(:[]).with("master").and_return(master_rev)
        allow(document.revisions).to receive(:[]).with("published").and_return(published_rev)

        expect(Revision).to receive(:new).with(document, master_rev.content, author, "", time, published_rev, master_rev).and_return(new_revision)
        expect(new_revision).to receive(:write!).with(document.repository, "refs/heads/published")

        revision = document.promote!('master', 'published', author, "", time)
      end
    end
  end
end
