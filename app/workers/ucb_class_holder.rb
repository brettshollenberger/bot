require "capybara/rails"
require 'twilio-ruby'

class UcbClassHolder
  include Sidekiq::Worker
  sidekiq_options queue: 'critical'

  def perform(class_match_id)
    match = UserUcbClassMatch.find(class_match_id)
    hold_url = place_hold(match)

    if !!(hold_url =~ /course\/register\/\d+/)
      hold =  UcbClassHold.create(
        user_id: match.user_id,
        ucb_class_id: match.ucb_class_id,
        hold_url: hold_url
      )

      phone_alert(hold)
      email_alert(hold)
    end
  end

  def email_alert(hold)
    UcbUpdateMailer.red_alert(hold).deliver_now
  end

  def phone_alert(hold)
    account_sid     = ENV["TWILIO_SID"]
    auth_token      = ENV["TWILIO_TOKEN"]
    outgoing_number = ENV["TWILIO_NUMBER"]
    twilio_url      = ENV["TWILIO_URL"]

    @client = Twilio::REST::Client.new account_sid, auth_token
    @client.api.account.calls.create(
      from: "+#{outgoing_number}",
      to: hold.user.phone,
      url: twilio_url
    )
  end

  def place_hold(match)
    require "capybara/rails"
    Capybara.current_driver = :selenium

    Capybara.javascript_driver = :headless_chrome
    Capybara.app_host = 'https://newyork.ucbtrainingcenter.com'
    session = Capybara::Session.new(:selenium, Rails.application)

    url = match.ucb_class.registration_url
    page = "https://newyork.ucbtrainingcenter.com/login?http_referer=#{url}"
    session.visit(page)
    session.find(:css, "form input[name='email']").set(match.user.email)
    session.find(:css, "form input[name='password']").set(match.user.ucb_password)
    session.find(:css, "input[value='Login'][type='submit']").click
    session.find(:css, "a.register_btn").click
    url = session.current_url
    session.driver.quit
    return url
  end
end
