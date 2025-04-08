# frozen_string_literal: true

require 'aws-sdk-s3'

module LetterOpenerWeb
  # Specialized class for Letter mapped to an S3 bucket
  class S3Letter < Letter
    attr_reader :page_limit, :page_next_continuation_token

    DEFAULT_PAGE_LIMIT = 20

    class << self
      delegate :s3_client, to: :delivery_method
    end
    delegate :s3_client, :delivery_method, to: 'self.class'

    def initialize(attributes, metadata = nil)
      @id = case attributes
            when ->(v) { v.respond_to?(:fetch) }  then attributes.fetch(:id)
            when ->(v) { v.respond_to?(:prefix) } then File.basename(attributes.prefix)
            else raise(ArgumentError, attributes.class)
            end

      super(id: @id)
      @metadata = metadata
      initialize_custom_fields
      base_dir_path.mkpath
      fetch_related_files
    end

    def initialize_custom_fields
      @sent_at = Time.at(@id.split('_').first.to_i)
      @page_limit = @metadata&.max_keys
      @page_next_continuation_token = @metadata.next_marker if @metadata.respond_to?(:next_marker)
      @page_next_continuation_token ||= @metadata.next_continuation_token if @metadata.respond_to?(:next_continuation_token)
    end

    def list_related_files
      s3_client.list_objects_v2(
        bucket: LetterOpenerWeb.config.s3_bucket,
        prefix: @id
      )
    end

    def base_dir_path
      Rails.root.join(base_dir)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def fetch_related_files
      return if style_exists?(:plain)
      Rails.logger.info("#{self.class}##{__method__} Retrieving #{@id}")

      list_related_files.contents.map do |item|
        next if item.key.ends_with?('/')

        LetterOpenerWeb.config.letters_location.join(item.key).tap do |response_target|
          s3_client.get_object(
            bucket: LetterOpenerWeb.config.s3_bucket,
            key: item.key,
            response_target: File.open(response_target, 'wb')
          )
        end
      end
    rescue StandardError
      FileUtils.rm_r(base_dir_path) if base_dir_path.exist?
      raise
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def delete
      s3_client.list_objects_v2(
        bucket: LetterOpenerWeb.config.s3_bucket,
        prefix: @id
      ).contents.each do |object|
        s3_client.delete_object(
          bucket: LetterOpenerWeb.config.s3_bucket,
          key: object.key
        )
      end
    end

    # Notice that there is key difference. Give that S3 ListObjectsV2 does not
    # allow to tune the sort order, we are unable to both paginate and sort the in a DESC way
    # So:
    #  * `Letter`: sort desc
    #  * `S3Letter`: sort asc
    def self.search(params = {})
      result = s3_client.list_objects_v2(
        bucket: LetterOpenerWeb.config.s3_bucket,
        delimiter: '/',
        max_keys: params.fetch(:limit, DEFAULT_PAGE_LIMIT),
        continuation_token: params.fetch(:next_continuation_token, nil)
      )
      result.common_prefixes
            .map { |item| new(item, result) }
            .reverse
    end

    def self.destroy_all
      s3_client.list_objects_v2(
        bucket: LetterOpenerWeb.config.s3_bucket
      ).contents.count do |object|
        s3_client.delete_object(
          bucket: LetterOpenerWeb.config.s3_bucket,
          key: object.key
        )
      end
    end

    def self.delivery_method
      ActionMailer::Base.delivery_methods.fetch(:letter_opener_web_s3)
    end
  end
end
