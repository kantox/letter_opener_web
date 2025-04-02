# frozen_string_literal: true

require 'aws-sdk-s3'

module LetterOpenerWeb
  class S3Letter < Letter

    attr_reader :page_limit, :page_continuation_token, :page_next_continuation_token

    class << self
      delegate :s3_client, to: :delivery_method
    end
    delegate :s3_client, :delivery_method, to: 'self.class'

    def initialize(attributes, collection = nil)
      @id = attributes.respond_to?(:fetch) ? attributes.fetch(:id) : File.basename(attributes.prefix)
      @sent_at = Time.at(@id.split('_').first.to_i)
      @page_limit = collection&.max_keys
      @page_next_continuation_token = collection&.next_marker
      fetch_inner_files
    end

    def fetch_inner_files
      root = Rails.root.join(LetterOpenerWeb.config.letters_location)
      return if root.join(@id).exist?

      root.join(@id).mkpath

      result = s3_client.list_objects_v2(
        bucket: delivery_method.bucket,
        prefix: @id
      )

      result.contents.each do |item|
        next if item.key.ends_with?('/')
        response_target = root.join(item.key)

        s3_client.get_object(
          bucket: delivery_method.bucket,
          key: item.key,
          response_target: File.open(response_target, 'wb')
        )
      end
    rescue
      root.join(@id).delete if root.join(@id).exists?
    end

    DEFAULT_PAGE_LIMIT = 20

    def self.search(params = {})
      result = s3_client.list_objects(
        bucket: delivery_method.bucket,
        delimiter: '/',
        max_keys: params.fetch(:limit, DEFAULT_PAGE_LIMIT),
        continuation_token: params.fetch(:next_continuation_token, nil)
      )
      result.common_prefixes.
             map { |item| new(item, result) }.
             sort_by(&:sent_at).
             reverse
    end

    def self.delivery_method
      @delivery_method ||= ActionMailer::Base.delivery_methods.fetch(:letter_opener_web_s3).new
    end

    def self.destroy_all
      count = 0
      s3_client.list_objects_v2(
        bucket: delivery_method.bucket
      ).contents.each do |object|
        s3_client.delete_object(
          bucket: delivery_method.bucket,
          key: object.key
        )
        count += 1
      end
      count
    end

    def delete
      s3_client.list_objects_v2(
        bucket: delivery_method.bucket,
        prefix: @id,
      ).contents.each do |object|
        s3_client.delete_object(
          bucket: delivery_method.bucket,
          key: object.key
        )
      end
    end
  end
end
