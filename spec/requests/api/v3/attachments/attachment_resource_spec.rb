#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2018 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See docs/COPYRIGHT.rdoc for more details.
#++

require 'spec_helper'
require 'rack/test'

describe 'API v3 Attachment resource', type: :request, content_type: :json do
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  let(:current_user) do
    FactoryBot.create(:user, member_in_project: project, member_through_role: role)
  end
  let(:project) { FactoryBot.create(:project, is_public: false) }
  let(:role) { FactoryBot.create(:role, permissions: permissions) }
  let(:permissions) do
    %i[view_work_packages view_wiki_pages delete_wiki_pages_attachments
       edit_work_packages edit_wiki_pages edit_messages]
  end
  let(:work_package) { FactoryBot.create(:work_package, author: current_user, project: project) }
  let(:attachment) { FactoryBot.create(:attachment, container: container) }
  let(:wiki) { FactoryBot.create(:wiki, project: project) }
  let(:wiki_page) { FactoryBot.create(:wiki_page, wiki: wiki) }
  let(:board) { FactoryBot.create(:board, project: project) }
  let(:board_message) { FactoryBot.create(:message, board: board) }
  let(:container) { work_package }

  before do
    allow(User).to receive(:current).and_return current_user
  end

  describe '#get' do
    subject(:response) { last_response }
    let(:get_path) { api_v3_paths.attachment attachment.id }

    %i[wiki_page work_package board_message].each do |attachment_type|
      context "with a #{attachment_type} attachment" do
        let(:container) { send(attachment_type) }

        context 'logged in user' do
          before do
            get get_path
          end

          it 'should respond with 200' do
            expect(subject.status).to eq(200)
          end

          it 'should respond with correct attachment' do
            expect(subject.body).to be_json_eql(attachment.filename.to_json).at_path('fileName')
          end

          context 'requesting nonexistent attachment' do
            let(:get_path) { api_v3_paths.attachment 9999 }

            it_behaves_like 'not found' do
              let(:id) { 9999 }
              let(:type) { 'Attachment' }
            end
          end

          context 'requesting attachments without sufficient permissions' do
            if attachment_type == :board_message
              let(:current_user) { FactoryBot.create(:user) }
            else
              let(:permissions) { [] }
            end

            it_behaves_like 'not found' do
              let(:type) { 'Attachment' }
            end
          end
        end
      end
    end
  end

  describe '#delete' do
    let(:path) { api_v3_paths.attachment attachment.id }

    before do
      delete path
    end

    subject(:response) { last_response }

    %i[wiki_page work_package board_message].each do |attachment_type|
      context "with a #{attachment_type} attachment" do
        let(:container) { send(attachment_type) }

        context 'with required permissions' do
          it 'responds with HTTP No Content' do
            expect(subject.status).to eq 204
          end

          it 'deletes the attachment' do
            expect(Attachment.exists?(attachment.id)).not_to be_truthy
          end

          context 'for a non-existent attachment' do
            let(:path) { api_v3_paths.attachment 1337 }

            it_behaves_like 'not found' do
              let(:id) { 1337 }
              let(:type) { 'Attachment' }
            end
          end
        end

        context 'without required permissions' do
          let(:permissions) { %i[view_work_packages view_wiki_pages] }

          it 'responds with 403' do
            expect(subject.status).to eq 403
          end

          it 'does not delete the attachment' do
            expect(Attachment.exists?(attachment.id)).to be_truthy
          end
        end
      end
    end
  end

  describe '#content' do
    let(:path) { api_v3_paths.attachment_content attachment.id }

    before do
      get path
    end

    subject(:response) { last_response }

    context 'with required permissions' do
      context 'for a local file' do
        let(:mock_file) { FileHelpers.mock_uploaded_file name: 'foobar.txt' }
        let(:attachment) do
          att = FactoryBot.create(:attachment, container: container, file: mock_file)

          att.file.store!
          att.send :write_attribute, :file, mock_file.original_filename
          att.send :write_attribute, :content_type, mock_file.content_type
          att.save!
          att
        end

        it 'responds with 200 OK' do
          expect(subject.status).to eq 200
        end

        it 'has the necessary headers' do
          expect(subject.headers['Content-Disposition'])
            .to eql "attachment; filename=#{mock_file.original_filename}"

          expect(subject.headers['Content-Type'])
            .to eql mock_file.content_type
        end

        it 'sends the file in binary' do
          expect(subject.body)
            .to match(mock_file.read)
        end
      end

      context 'for a remote file' do
        let(:remote_url) { 'http://some_service.org/blubs.gif' }
        let(:mock_file) { FileHelpers.mock_uploaded_file name: 'foobar.txt' }
        let(:attachment) do
          FactoryBot.create(:attachment, container: container, file: mock_file) do |a|
            # need to mock here to avoid dependency on external service
            allow_any_instance_of(Attachment)
              .to receive(:external_url)
              .and_return(remote_url)
          end
        end

        it 'responds with 302 Redirect' do
          expect(subject.status).to eq 302
          expect(subject.headers['Location'])
            .to eql remote_url
        end
      end
    end
  end
end
