require "base64"

module Colonel
  # Public: a serialization tool for Colonel::Document
  class Serializer

    class << self

      # Public: serializes a document with full history and writes to a stream
      #
      # document - a Document instance
      # ostream  - an instance of IO to write to
      def generate(documents, ostream)
        documents = [documents] unless documents.respond_to?(:each)
        documents.each do |document|
          ostream.write "document: #{document.name}\n"
          ostream.write "objects:\n"

          repo = document.repository

          root_oid = repo.references["refs/tags/root"].target_id
          write_commit(ostream, repo, root_oid, repo.lookup(root_oid))

          repo.references.each do |ref|
            oid = ref.target_id
            while(oid && oid != root_oid)
              commit = repo.lookup(oid)
              write_commit(ostream, repo, oid, commit)

              break if commit.parent_ids.empty?
              oid = commit.parent_ids.first # walk down only
            end
          end

          ostream.write "references:\n"
          ostream.write serialize_hash({name: "HEAD", type: :symbolic, target: "refs/heads/master"})
          ostream.write("\n")

          repo.references.each do |ref|
            ostream.write(serialize_hash({name: ref.name, type: :oid, target: ref.target_id}))
            ostream.write("\n")
          end
        end
      end

      # Public: loads a series of documents from a string produced by `generate`
      #
      # istream   - input stream to read from
      #
      # returns a document instance
      def load(stream, &block)
        document = nil
        repo = nil
        reading = :header

        while(line = stream.readline) # or break in yield!
          case line
          when /^document:\s*(.+)$/
            reading = :header

            if document
              finalize_document(document)
              yield if block_given?
            end

            raise RuntimeError, "Malformed document header" if $~[1].empty?

            document = Document.new($~[1])
            repo = document.repository
          when /^references:$/
            raise RuntimeError, "Malformed document, unexpected references section" unless reading == :object
            reading = :ref
          when /^objects:$/
            raise RuntimeError, "Malformed document, unexpected objects section" unless reading == :header
            reading = :object
          else
            case reading
            when :ref
              read_reference(repo, line)
            when :object
              read_object(repo, line)
            else
              raise RuntimeError, "Malformed input, expected document header, got #{line}"
            end
          end

          if stream.eof?
            if reading == :ref
              doc = finalize_document(document)
              yield if block_given?
            end

            break
          end
        end
      end

      private

      def write_commit(stream, repo, oid, commit)
        write_object(stream, oid, commit)

        tree = commit.tree
        write_object(stream, tree.oid, tree)

        content_id = tree.first[:oid]
        content = repo.lookup(content_id)

        write_object(stream, content_id, content)
      end

      def write_object(stream, id, object)
        raw = object.read_raw
        hash = {oid: raw.oid, type: raw.type, data: Base64.strict_encode64(raw.data).strip, len: raw.len}

        stream.write(serialize_hash(hash))
        stream.write("\n")
      end

      def read_reference(repo, ref)
        ref = load_hash(ref) rescue raise(RuntimeError, "expected reference, found: #{line}")

        if repo.references[ref['name']]
          repo.references.update(ref["name"], ref["target"])
        else
          repo.references.create(ref["name"], ref["target"])
        end
      end

      def finalize_document(document)
        document.load!
        document.index.register(document.name)

        document
      end

      def read_object(repo, obj)
        obj = load_hash(obj) rescue raise(RuntimeError, "expected object, found: #{line}")
        data = Base64.strict_decode64(obj['data'])

        raise RuntimeError, "Data length mismatch! dump: #{obj["len"]}, actuall: #{data.bytesize}" unless data.bytesize == obj['len']

        oid = repo.write(data, obj['type'].to_sym)
        raise RuntimeError, "oid mismatch! read: #{obj["oid"]}, got: #{oid}" unless oid == obj['oid']
      end

      def serialize_hash(hash)
        JSON.generate(hash)
      end

      def load_hash(string)
        JSON.parse(string)
      end
    end
  end
end
