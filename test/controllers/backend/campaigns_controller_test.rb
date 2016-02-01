require 'test_helper'

module Backend
  class CampaignsControllerTest < ActionController::TestCase
    test_restfully_all_actions except: :open

    test 'open action in post mode' do
      post :open, {:locale=>@locale, activity_id: activities(:activities_001).id, id: campaigns(:campaigns_001).id }
      assert_redirected_to backend_campaign_path(campaigns(:campaigns_001))
    end
  end
end
