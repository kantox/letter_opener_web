# frozen_string_literal: true

RSpec.describe LetterOpenerWeb::S3Letter do
  let(:location) do
    Pathname.new(__dir__).join('..', '..', 'tmp').cleanpath.join(LetterOpenerWeb.config.letters_location)
  end
  let(:s3_client) { Aws::S3::Client.new(stub_responses: true) }
  let(:s3_common_prefixes_struct) { Struct.new(:common_prefixes, :max_keys, :next_marker) }
  let(:s3_collection_struct) { Struct.new(:contents, :max_keys, :next_marker) }
  let(:s3_object_struct) { Struct.new(:key) }
  let(:s3_common_prefix_struct) { Struct.new(:prefix) }

  before do
    # Forces a new client S3 to be instanciated and cached
    allow(LetterOpenerWeb::S3DeliveryMethod).to receive(:s3_client).and_return(s3_client)
    allow(LetterOpenerWeb.config).to receive(:s3_bucket).and_return('my-bucket')
  end

  after do
    FileUtils.rm_r(location) if location.exist?
  end

  describe '.new' do
    subject(:s3_letter) { described_class.new(attributes) }

    shared_context 'successful letter built' do
      let(:list_objects_mock) do
        allow(s3_client).to receive(:list_objects_v2).and_return(
          s3_collection_struct.new(
            [
              s3_object_struct.new('1743105025_90816_58d0dfe/plain.html'),
              s3_object_struct.new('1743105025_90816_58d0dfe/rich.html'),
              s3_object_struct.new('1743105025_90816_58d0dfe/attachment.pdf'),
              s3_object_struct.new('1743105025_90816_58d0dfe/attachments/file.pdf')
            ],
            10,
            next_marker: nil
          )
        )
      end

      let(:get_object_mock) do
        allow(s3_client).to receive(:get_object).exactly(4).times
      end

      let(:response_target_check) do
        proc { |file, filename| file.is_a?(File) && file.path == location.join(filename) }
      end

      before do
        list_objects_mock
        get_object_mock
        s3_letter
      end

      it { is_expected.to be_a(described_class) }
      it { expect(s3_letter.id).to eq('1743105025_90816_58d0dfe') }
      it { expect(s3_letter.sent_at).to eq(Time.at(1_743_105_025)) }
      it { expect(s3_letter.base_dir_path).to be_exist }
      it { expect(s3_letter.attachments_dir_path).to be_exist }

      it do
        expect(s3_client).to have_received(:list_objects_v2).with(
          bucket: 'my-bucket',
          prefix: s3_letter.id
        )
      end

      it do
        expect(s3_client).to have_received(:get_object).with(
          bucket: 'my-bucket',
          key: '1743105025_90816_58d0dfe/plain.html',
          response_target: satisfy do |f|
            f.is_a?(File) && f.path == location.join('1743105025_90816_58d0dfe/plain.html').to_s
          end
        ).once
      end

      it do
        expect(s3_client).to have_received(:get_object).with(
          bucket: 'my-bucket',
          key: '1743105025_90816_58d0dfe/rich.html',
          response_target: satisfy do |f|
            f.is_a?(File) && f.path == location.join('1743105025_90816_58d0dfe/rich.html').to_s
          end
        ).once
      end

      it do
        expect(s3_client).to have_received(:get_object).with(
          bucket: 'my-bucket',
          key: '1743105025_90816_58d0dfe/attachment.pdf',
          response_target: satisfy do |f|
            f.is_a?(File) && f.path == location.join('1743105025_90816_58d0dfe/attachment.pdf').to_s
          end
        ).once
      end

      it do
        expect(s3_client).to have_received(:get_object).with(
          bucket: 'my-bucket',
          key: '1743105025_90816_58d0dfe/attachments/file.pdf',
          response_target: satisfy do |f|
            f.is_a?(File) && f.path == location.join('1743105025_90816_58d0dfe/attachments/file.pdf').to_s
          end
        ).once
      end

      context 'with some metadata' do
        subject(:s3_letter) { described_class.new(attributes, metadata) }

        let(:metadata) do
          Struct.new(:max_keys, :next_marker).new(
            42,
            'foo'
          )
        end

        it { expect(s3_letter.page_limit).to eq(42) }
        it { expect(s3_letter.page_next_continuation_token).to eq('foo') }
      end
    end

    shared_context 'when there is an issue retrieving the data' do
      let(:list_objects_mock) do
        allow(s3_client).to receive(:list_objects_v2).and_raise(StandardError)
      end

      before { list_objects_mock }

      it 'deletes the letter folder' do
        expect { s3_letter }.to raise_error(StandardError)

        expect(location.join('1743105025_90816_58d0dfe')).not_to be_exist
      end
    end

    context 'with a plain String id' do
      let(:attributes) { { id: '1743105025_90816_58d0dfe' } }

      it_behaves_like 'successful letter built'
      it_behaves_like 'when there is an issue retrieving the data'
    end

    context 'with a s3 data with prefix' do
      let(:attributes) { s3_common_prefix_struct.new('1743105025_90816_58d0dfe') }

      it_behaves_like 'successful letter built'
      it_behaves_like 'when there is an issue retrieving the data'
    end
  end

  describe '.search' do
    subject(:search_results) { described_class.search }
    let(:first_letter) { search_results.first }
    let(:last_letter) { search_results.last }
    let(:list_objects_mock) do
      allow(s3_client).to receive(:list_objects_v2).and_return(
        s3_common_prefixes_struct.new(
          [
            s3_common_prefix_struct.new('1743105025_90816_58d0dfe'),
            s3_common_prefix_struct.new('1743105026_90816_58d0dfd'),
            s3_common_prefix_struct.new('1743105027_90816_58d0dff')
          ],
          10,
          next_marker: nil
        )
      )
    end

    before do
      list_objects_mock
      # Tested in initialization
      allow_any_instance_of(described_class).to receive(:fetch_related_files)
    end

    it do
      expect(search_results.length).to eq(3)
    end

    it 'returns a list of ordered letters' do
      expect(first_letter.sent_at).to be < last_letter.sent_at
    end

    context 'with next_continuation_token' do
      let(:search_results) { described_class.search(next_continuation_token: 'foo') }

      before { search_results }

      it do
        expect(s3_client).to have_received(:list_objects_v2).with(
          bucket: 'my-bucket',
          delimiter: '/',
          max_keys: 20,
          prefix: nil,
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
          delimiter: '/',
          max_keys: 2,
          prefix: nil,
          continuation_token: nil
        )
      end
    end

    context 'with date' do
      let(:search_results) { described_class.search(limit: 2, date: today.strftime('%F')) }
      let(:today) { Date.today }

      before { search_results }

      it do
        expect(s3_client).to have_received(:list_objects_v2).with(
          bucket: 'my-bucket',
          delimiter: '/',
          prefix: "#{today.strftime('%F')}T",
          max_keys: 2,
          continuation_token: nil
        )
      end
    end

    context 'with date and time' do
      let(:search_results) { described_class.search(limit: 2, date: today.strftime('%F'), time: '23:59') }
      let(:today) { Date.today }

      before { search_results }

      it do
        expect(s3_client).to have_received(:list_objects_v2).with(
          bucket: 'my-bucket',
          delimiter: '/',
          prefix: "#{today.strftime('%F')}T23-59",
          max_keys: 2,
          continuation_token: nil
        )
      end
    end

    context 'with time' do
      let(:search_results) { described_class.search(limit: 2, time: '23:59') }
      let(:today) { Date.today }

      it do
        expect { search_results }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.destroy_all' do
    subject(:destroy_all_results) { described_class.destroy_all }

    let(:delete_object_mock) do
      allow(s3_client).to receive(:delete_object).and_return(true)
    end

    let(:list_objects_mock) do
      allow(s3_client).to receive(:list_objects_v2).and_return(
        s3_collection_struct.new(
          [
            s3_object_struct.new('1743105025_90816_58d0dfe/pain.html'),
            s3_object_struct.new('1743105025_90816_58d0dfe/rich.html'),
            s3_object_struct.new('1743105026_90816_58d0dfd/plain.html'),
            s3_object_struct.new('1743105027_90816_58d0dfd/rich.html'),
            s3_object_struct.new('1743105027_90816_58d0dfd/attachment.pdf'),
            s3_object_struct.new('1743105028_90816_58d0dff')
          ],
          10,
          next_marker: nil
        )
      )
    end

    before do
      list_objects_mock
      delete_object_mock
      destroy_all_results
    end

    it { is_expected.to eq(6) }

    it do
      expect(s3_client).to have_received(:delete_object).with(bucket: 'my-bucket',
                                                              key: '1743105025_90816_58d0dfe/pain.html')
      expect(s3_client).to have_received(:delete_object).with(bucket: 'my-bucket',
                                                              key: '1743105025_90816_58d0dfe/rich.html')
      expect(s3_client).to have_received(:delete_object).with(bucket: 'my-bucket',
                                                              key: '1743105026_90816_58d0dfd/plain.html')
      expect(s3_client).to have_received(:delete_object).with(bucket: 'my-bucket',
                                                              key: '1743105027_90816_58d0dfd/rich.html')
      expect(s3_client).to have_received(:delete_object).with(bucket: 'my-bucket',
                                                              key: '1743105027_90816_58d0dfd/attachment.pdf')
      expect(s3_client).to have_received(:delete_object).with(bucket: 'my-bucket', key: '1743105028_90816_58d0dff')
    end
  end
end
