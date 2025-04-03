# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LetterOpenerWeb::LettersController do
  routes { LetterOpenerWeb::Engine.routes }

  after(:each) { LetterOpenerWeb.reset! }

  # TODO: Deprecated rails 5.2 and ruby 2.6
  let(:expected_html_content_type) do
    if Rails.version.to_f < 6
      'text/html'
    else
      'text/html; charset=utf-8'
    end
  end

  describe 'GET index' do
    let(:params) { {} }

    context 'when not configured with an s3 bucket' do
      before do
        allow(LetterOpenerWeb::Letter).to receive(:search)
        allow(LetterOpenerWeb::S3Letter).to receive(:search)
        get :index, params: params
      end

      it 'searches for all file system letters' do
        expect(LetterOpenerWeb::Letter).to have_received(:search).with(params)
      end

      it 'does not search for s3 letters' do
        expect(LetterOpenerWeb::S3Letter).not_to have_received(:search)
      end

      context 'with pagination params' do
        let(:params) { { next_continuation_token: 'foo', limit: '20' } }

        it do
          expect(LetterOpenerWeb::Letter).to have_received(:search)
                                         .with(ActionController::Parameters.new(params).permit!)
        end
      end

      it 'returns an HTML 200 response' do
        expect(response.status).to eq(200)
        expect(response.content_type).to eq(expected_html_content_type)
      end
    end

    context 'when configured for S3Letter model' do
      before do
        allow(LetterOpenerWeb::Letter).to receive(:search)
        allow(LetterOpenerWeb::S3Letter).to receive(:search)
        allow(LetterOpenerWeb.config).to receive(:letter_model).and_return(LetterOpenerWeb::S3Letter.name)
        get :index, params: params
      end

      context 'with pagination params' do
        let(:params) { { next_continuation_token: '10', limit: '20' } }

        it do
          expect(LetterOpenerWeb::S3Letter).to have_received(:search)
            .with(ActionController::Parameters.new(params).permit!)
        end
      end

      it 'searches for all file system letters' do
        expect(LetterOpenerWeb::S3Letter).to have_received(:search).with(params)
      end

      it 'does not search for s3 letters' do
        expect(LetterOpenerWeb::Letter).not_to have_received(:search)
      end

      it 'returns an HTML 200 response' do
        expect(response.status).to eq(200)
        expect(response.content_type).to eq(expected_html_content_type)
      end
    end
  end

  describe 'GET show' do
    let(:id)         { 'an-id' }
    let(:rich_text)  { 'rich text href="plain.html"' }
    let(:plain_text) { 'plain text href="rich.html"' }

    shared_examples 'found letter examples' do |letter_style|
      let(:letter) { double(:letter, rich_text: rich_text, plain_text: plain_text, id: id) }

      before(:each) do
        expect(LetterOpenerWeb::Letter).to receive(:find).with(id).and_return(letter)
        expect(letter).to receive(:valid?).and_return(true)
        get :show, params: { id: id, style: letter_style }
      end

      it 'renders an HTML 200 response' do
        expect(response.status).to eq(200)
        expect(response.content_type).to eq(expected_html_content_type)
      end
    end

    shared_examples 'found s3 letter examples' do |letter_style|
      let(:s3_letter) { double(:s3_letter, rich_text: rich_text, plain_text: plain_text, id: id) }

      before(:each) do
        allow(LetterOpenerWeb.config).to receive(:letter_model).and_return(LetterOpenerWeb::S3Letter.name)
        expect(LetterOpenerWeb::Letter).to receive(:find).never
        expect(LetterOpenerWeb::S3Letter).to receive(:find).with(id).and_return(s3_letter)
        expect(s3_letter).to receive(:valid?).and_return(true)
        get :show, params: { id: id, style: letter_style }
      end

      it 'renders an HTML 200 response' do
        expect(response.status).to eq(200)
        expect(response.content_type).to eq(expected_html_content_type)
      end
    end

    context 'rich text version' do
      include_examples 'found letter examples', 'rich'
      include_examples 'found s3 letter examples', 'rich'

      it 'renders the rich text contents' do
        expect(response.body).to match(/^rich text/)
      end

      it 'fixes plain text link' do
        expect(response.body).not_to match(/href="plain.html"/)
        expect(response.body).to match(/href="#{Regexp.escape letter_path(id: id, style: 'plain')}"/)
      end
    end

    context 'plain text version' do
      include_examples 'found letter examples', 'plain'
      include_examples 'found s3 letter examples', 'plain'

      it 'renders the plain text contents' do
        expect(response.body).to match(/^plain text/)
      end

      it 'fixes rich text link' do
        expect(response.body).not_to match(/href="rich.html"/)
        expect(response.body).to match(/href="#{Regexp.escape letter_path(id: id, style: 'rich')}"/)
      end
    end

    context 'with wrong parameters' do
      it 'should return 404 when invalid id given' do
        get :show, params: { id: id, style: 'rich' }
        expect(response.status).to eq(404)
      end
    end
  end

  describe 'GET attachment' do
    let(:id)              { 'an-id' }
    let(:attachment_path) { 'path/to/attachment' }
    let(:file_name)       { 'image.jpg' }
    let(:letter)          { double(:letter, attachments: { file_name => attachment_path }, id: id) }

    before do
      allow(LetterOpenerWeb::Letter).to receive(:find).with(id).and_return(letter)
      allow(letter).to receive(:valid?).and_return(true)
    end

    context 'when the file exists' do
      before do
        # Stub a 200 response b/c `send_file` will 204 when the file doesn't actually exist
        allow(controller).to receive(:send_file) { controller.head :ok }
      end

      it 'sends the file as an inline attachment' do
        get :attachment, params: { id: id, file: file_name }

        expect(response.status).to eq(200)
        expect(controller).to have_received(:send_file)
          .with(attachment_path, filename: file_name, disposition: 'inline')
      end

      context 'when file name includes a dot' do
        let(:file_name) { 'image.dot.jpg' }

        it 'sends the file as an inline attachment' do
          expect(controller).to receive(:send_file).with(attachment_path, filename: file_name,
                                                                          disposition: 'inline')
          get :attachment, params: { id: id, file: file_name }
          expect(response.status).to eq(200)
        end
      end
    end

    it "returns a 404 if attachment file can't be found" do
      get :attachment, params: { id: id, file: 'unknown.woot' }

      expect(response.status).to eq(404)
    end
  end

  describe 'DELETE clear' do
    it 'removes all letters' do
      expect(LetterOpenerWeb::Letter).to receive(:destroy_all)
      delete :clear
    end

    it 'redirects back to index' do
      delete :clear
      expect(response).to redirect_to(letters_path)
    end
  end

  describe 'DELETE destroy' do
    let(:id) { 'an-id' }

    it 'removes the selected letter' do
      allow_any_instance_of(LetterOpenerWeb::Letter).to receive(:valid?).and_return(true)
      expect_any_instance_of(LetterOpenerWeb::Letter).to receive(:delete)
      delete :destroy, params: { id: id }
    end

    it 'throws a 404 if attachment is outside of the letters base path' do
      bad_id = '../an-id'

      allow_any_instance_of(LetterOpenerWeb::Letter).to receive(:valid?).and_return(false)
      expect_any_instance_of(LetterOpenerWeb::Letter).not_to receive(:delete)

      delete :destroy, params: { id: bad_id }

      expect(response.status).to eq(404)
    end
  end
end
