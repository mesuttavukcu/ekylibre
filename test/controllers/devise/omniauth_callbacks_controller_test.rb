require 'test_helper'
module Devise
  class OmniauthCallbacksControllerTest < Ekylibre::Testing::ApplicationControllerTestCase::WithFixtures
    # TODO: Re-activate #passthru and #failure tests
    test_restfully_all_actions except: %i[passthru failure]
  end
end
