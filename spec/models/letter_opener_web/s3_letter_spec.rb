# frozen_string_literal: true

RSpec.describe LetterOpenerWeb::S3Letter do
  let(:location) { Pathname.new(__dir__).join('..', '..', 'tmp').cleanpath }
  let(:s3_client) { Aws::S3::Client.new(stub_responses: true) }
  let(:s3_collection_struct) { Struct.new(:contents, :max_keys, :continuation_token) }
  let(:s3_item_struct) { Struct.new(:key, :last_modified) }

  before do
    LetterOpenerWeb.configure { |config| config.s3_bucket = 'my-bucket' }
    described_class.delivery_method.s3_client = s3_client
    allow(s3_client).to receive(:list_objects_v2).and_return(
      s3_collection_struct.new([
        s3_item_struct.new(
          '1743105025_90816_58d0dfe/',
          Time.parse("2014-11-21T19:40:05.000Z")
        ),
        s3_item_struct.new(
          '1743105025_90816_58d0dfd/',
          Time.parse("2014-11-20T19:40:05.000Z")
        ),
        s3_item_struct.new(
          '1743105025_90816_58d0dff/',
          Time.parse("2014-11-22T19:40:05.000Z")
        )
      ])
    )
  end

  after do
    LetterOpenerWeb.configure { |config| config.s3_bucket = nil }
    LetterOpenerWeb.reset!
  end

  describe '.search' do
    let(:search_results) { described_class.search }

    let(:first_letter) do
      search_results.first
    end

    let(:last_letter) do
      search_results.last
    end

    it do
      expect(search_results.length).to eq(3)
    end

    it 'returns a list of ordered letters' do
      expect(first_letter.sent_at).to be > last_letter.sent_at
    end

    context 'with offset' do
      let(:search_results) { described_class.search(offset: 'foo') }

      before { search_results }

      it do
        expect(s3_client).to have_received(:list_objects_v2).with(
          bucket: 'my-bucket',
          max_keys: 50,
          continuation_token: 'foo'
        )
      end
    end

    context 'with limit' do
      let(:search_results) { described_class.search(limit: 2) }

      before { search_results }

      it do
        expect(s3_client).to have_received(:list_objects_v2).with(
          bucket: 'my-bucket',
          max_keys: 2,
          continuation_token: nil
        )
      end
    end
  end
end
