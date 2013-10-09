require 'test_helper'

class FedExTest < MiniTest::Unit::TestCase
  def setup
    @packages               = TestFixtures.packages
    @locations              = TestFixtures.locations
    @carrier                = FedEx.new(:key => '1111', :password => '2222', :account => '3333', :login => '4444')
    @tracking_response      = xml_fixture('fedex/tracking_response')
  end
  
  def test_initialize_options_requirements
    assert_raises ArgumentError do FedEx.new end
    assert_raises ArgumentError do FedEx.new(:login => '999999999') end
    assert_raises ArgumentError do FedEx.new(:password => '7777777') end
    FedEx.new(:key => '999999999', :password => '7777777', :account => '123', :login => '123')
  end

  def test_business_days
    today = DateTime.civil(2013, 3, 12, 0, 0, 0, "-4")

    Timecop.freeze(today) do
      assert_equal DateTime.civil(2013, 3, 13, 0, 0, 0, "-4"), @carrier.send(:business_days_from, today, 1)
      assert_equal DateTime.civil(2013, 3, 15, 0, 0, 0, "-4"), @carrier.send(:business_days_from, today, 3)
      assert_equal DateTime.civil(2013, 3, 19, 0, 0, 0, "-4"), @carrier.send(:business_days_from, today, 5)
    end
  end

  def test_turn_around_time_default
    mock_response = xml_fixture('fedex/ottawa_to_beverly_hills_rate_response').gsub('<v6:DeliveryTimestamp>2011-07-29</v6:DeliveryTimestamp>', '')

    today = DateTime.civil(2013, 3, 11, 0, 0, 0, "-4")

    Timecop.freeze(today) do
      delivery_date = Date.today + 7.days # FIVE_DAYS in fixture response, plus weekend
      timestamp = Time.now.iso8601
      @carrier.expects(:commit).with do |request, options|
        parsed_response = Hash.from_xml(request)
        parsed_response['RateRequest']['RequestedShipment']['ShipTimestamp'] == timestamp
      end.returns(mock_response)

      destination = ActiveMerchant::Shipping::Location.from(@locations[:beverly_hills].to_hash, :address_type => :commercial)
      response = @carrier.find_rates @locations[:ottawa], destination, @packages[:book], :test => true
      assert_equal [delivery_date, delivery_date], response.rates.first.delivery_range
    end
  end

  def test_turn_around_time
    mock_response = xml_fixture('fedex/ottawa_to_beverly_hills_rate_response').gsub('<v6:DeliveryTimestamp>2011-07-29</v6:DeliveryTimestamp>', '')
    Timecop.freeze(DateTime.new(2013, 3, 11)) do
      delivery_date = Date.today + 8.days # FIVE_DAYS in fixture response, plus turn_around_time, plus weekend
      timestamp = (Time.now + 1.day).iso8601
      @carrier.expects(:commit).with do |request, options|
        parsed_response = Hash.from_xml(request)
        parsed_response['RateRequest']['RequestedShipment']['ShipTimestamp'] == timestamp
      end.returns(mock_response)

      destination = ActiveMerchant::Shipping::Location.from(@locations[:beverly_hills].to_hash, :address_type => :commercial)
      response = @carrier.find_rates @locations[:ottawa], destination, @packages[:book], :turn_around_time => 24, :test => true

      assert_equal [delivery_date, delivery_date], response.rates.first.delivery_range
    end
  end
  
  def test_find_tracking_info_should_return_a_tracking_response
    @carrier.expects(:commit).returns(@tracking_response)
    assert_instance_of ActiveMerchant::Shipping::TrackingResponse, @carrier.find_tracking_info('077973360403984', :test => true)
  end
  
  def test_find_tracking_info_should_mark_shipment_as_delivered
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal true, @carrier.find_tracking_info('077973360403984').delivered?
  end

  def test_find_tracking_info_should_return_correct_carrier
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal :fedex, @carrier.find_tracking_info('077973360403984').carrier
  end

  def test_find_tracking_info_should_return_correct_carrier_name
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal 'FedEx', @carrier.find_tracking_info('077973360403984').carrier_name
  end

  def test_find_tracking_info_should_return_correct_status
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal :delivered, @carrier.find_tracking_info('077973360403984').status
  end
  
  def test_find_tracking_info_should_return_correct_status_code
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal 'dl', @carrier.find_tracking_info('077973360403984').status_code.downcase
  end

  def test_find_tracking_info_should_return_correct_status_description
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal 'delivered', @carrier.find_tracking_info('1Z5FX0076803466397').status_description.downcase
  end

  def test_find_tracking_info_should_return_delivery_signature
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal 'KKING', @carrier.find_tracking_info('077973360403984').delivery_signature
  end

  def test_find_tracking_info_should_return_destination_address
    @carrier.expects(:commit).returns(@tracking_response)
    result = @carrier.find_tracking_info('077973360403984')
    assert_equal 'sacramento', result.destination.city.downcase
    assert_equal 'CA', result.destination.state
  end

  def test_find_tracking_info_should_gracefully_handle_missing_destination_information
    @carrier.expects(:commit).returns(xml_fixture('fedex/tracking_response_no_destination'))
    result = @carrier.find_tracking_info('077973360403984')
    assert_equal 'unknown', result.destination.city.downcase
    assert_equal 'unknown', result.destination.state
    assert_equal 'ZZ', result.destination.country.code(:alpha2).to_s
  end

  def test_find_tracking_info_should_return_correct_shipper_address
    @carrier.expects(:commit).returns(xml_fixture('fedex/tracking_response_with_shipper_address'))
    response = @carrier.find_tracking_info('927489999894450502838')
    assert_equal 'wallingford', response.shipper_address.city.downcase
    assert_equal 'CT', response.shipper_address.state
  end

  def test_find_tracking_info_should_gracefully_handle_missing_shipper_address
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('077973360403984')
    assert_equal nil, response.shipper_address
  end

  def test_find_tracking_info_should_return_correct_ship_time
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('927489999894450502838')
    assert_equal Time.parse("2008-12-03T00:00:00").utc, response.ship_time
  end

  def test_find_tracking_info_should_gracefully_handle_missing_ship_time
    @carrier.expects(:commit).returns(xml_fixture('fedex/tracking_response_no_ship_time'))
    response = @carrier.find_tracking_info('927489999894450502838')
    assert_equal nil, response.ship_time
  end


  def test_find_tracking_info_should_return_origin_address
    @carrier.expects(:commit).returns(@tracking_response)
    result = @carrier.find_tracking_info('077973360403984')
    assert_equal 'nashville', result.origin.city.downcase
    assert_equal 'TN', result.origin.state
  end

  def test_find_tracking_info_should_parse_response_into_correct_number_of_shipment_events
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('077973360403984', :test => true)
    assert_equal 6, response.shipment_events.size
  end
  
  def test_find_tracking_info_should_return_shipment_events_in_ascending_chronological_order
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('077973360403984', :test => true)
    assert_equal response.shipment_events.map(&:time).sort, response.shipment_events.map(&:time)
  end

  def test_find_tracking_info_should_not_include_events_without_an_address
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('077973360403984', :test => true)
    assert_nil response.shipment_events.find{|event| event.name == 'Shipment information sent to FedEx' }
  end
  
  def test_building_request_with_address_type_commercial_should_not_include_residential
    mock_response = xml_fixture('fedex/ottawa_to_beverly_hills_rate_response')
    expected_request = xml_fixture('fedex/ottawa_to_beverly_hills_commercial_rate_request')
    Time.any_instance.expects(:to_xml_value).returns("2009-07-20T12:01:55-04:00")

    @carrier.expects(:commit).with {|request, test_mode| Hash.from_xml(request) == Hash.from_xml(expected_request) && test_mode}.returns(mock_response)
    destination = ActiveMerchant::Shipping::Location.from(@locations[:beverly_hills].to_hash, :address_type => :commercial)
    response = @carrier.find_rates( @locations[:ottawa],
                                    destination,
                                    @packages.values_at(:book, :wii), :test => true)
  end
  
  def test_building_request_and_parsing_response
    expected_request = xml_fixture('fedex/ottawa_to_beverly_hills_rate_request')
    mock_response = xml_fixture('fedex/ottawa_to_beverly_hills_rate_response')
    Time.any_instance.expects(:to_xml_value).returns("2009-07-20T12:01:55-04:00")
    
    @carrier.expects(:commit).with {|request, test_mode| Hash.from_xml(request) == Hash.from_xml(expected_request) && test_mode}.returns(mock_response)
    response = @carrier.find_rates( @locations[:ottawa],
                                    @locations[:beverly_hills],
                                    @packages.values_at(:book, :wii), :test => true)
    assert_equal ["FedEx Ground"], response.rates.map(&:service_name)
    assert_equal [3836], response.rates.map(&:price)
    
    assert response.success?, response.message
    assert_instance_of Hash, response.params
    assert_instance_of String, response.xml
    assert_instance_of Array, response.rates
    assert response.rates.length > 0, "There should've been more than 0 rates returned"
    
    rate = response.rates.first
    assert_equal 'FedEx', rate.carrier
    assert_equal 'CAD', rate.currency
    assert_instance_of Fixnum, rate.total_price
    assert_instance_of Fixnum, rate.price
    assert_instance_of String, rate.service_name
    assert_instance_of String, rate.service_code
    assert_instance_of Array, rate.package_rates
    assert_equal @packages.values_at(:book, :wii), rate.packages
    
    package_rate = rate.package_rates.first
    assert_instance_of Hash, package_rate
    assert_instance_of Package, package_rate[:package]
    assert_nil package_rate[:rate]
  end
  
  def test_service_name_for_code
    FedEx::ServiceTypes.each do |capitalized_name, readable_name|
      assert_equal readable_name, FedEx.service_name_for_code(capitalized_name)
    end
  end
  
  def test_service_name_for_code_handles_yet_unknown_codes
    assert_equal "FedEx Express Saver Saturday Delivery", FedEx.service_name_for_code('FEDEX_EXPRESS_SAVER_SATURDAY_DELIVERY')
    assert_equal "FedEx Some Weird Rate", FedEx.service_name_for_code('SOME_WEIRD_RATE')
  end
  
  def test_returns_gbp_instead_of_ukl_currency_for_uk_rates
    mock_response = xml_fixture('fedex/ottawa_to_beverly_hills_rate_response').gsub('CAD', 'UKL')
    Time.any_instance.expects(:to_xml_value).returns("2009-07-20T12:01:55-04:00")
    
    @carrier.expects(:commit).returns(mock_response)
    response = @carrier.find_rates( @locations[:ottawa],
                                    @locations[:beverly_hills],
                                    @packages.values_at(:book, :wii), :test => true)
    assert_equal ["FedEx Ground"], response.rates.map(&:service_name)
    assert_equal [3836], response.rates.map(&:price)
    
    assert response.success?, response.message
    assert response.rates.length > 0, "There should've been more than 0 rates returned"
    
    response.rates.each do |rate|
      assert_equal 'FedEx', rate.carrier
      assert_equal 'GBP', rate.currency
    end
  end

  def test_returns_sgd_instead_of_sid_currency_for_signapore_rates
    mock_response = xml_fixture('fedex/ottawa_to_beverly_hills_rate_response').gsub('CAD', 'SID')
    Time.any_instance.expects(:to_xml_value).returns("2009-07-20T12:01:55-04:00")
    
    @carrier.expects(:commit).returns(mock_response)
    response = @carrier.find_rates( @locations[:ottawa],
                                    @locations[:beverly_hills],
                                    @packages.values_at(:book, :wii), :test => true)
    assert_equal ["FedEx Ground"], response.rates.map(&:service_name)
    assert_equal [3836], response.rates.map(&:price)
    
    assert response.success?, response.message
    assert response.rates.length > 0, "There should've been more than 0 rates returned"
    
    response.rates.each do |rate|
      assert_equal 'FedEx', rate.carrier
      assert_equal 'SGD', rate.currency
    end
  end

  def test_delivery_range_based_on_delivery_date
    mock_response = xml_fixture('fedex/ottawa_to_beverly_hills_rate_response').gsub('CAD', 'UKL')

    @carrier.expects(:commit).returns(mock_response)
    rate_estimates = @carrier.find_rates( @locations[:ottawa],
                                    @locations[:beverly_hills],
                                    @packages.values_at(:book, :wii), :test => true)

    delivery_date = Date.new(2011, 7, 29)
    assert_equal delivery_date, rate_estimates.rates[0].delivery_date
    assert_equal [delivery_date] * 2, rate_estimates.rates[0].delivery_range
  end

  def test_delivery_date_from_transit_time
    mock_response = xml_fixture('fedex/raterequest_reply').gsub('CAD', 'UKL')

    @carrier.expects(:commit).returns(mock_response)

    today = DateTime.civil(2013, 3, 15, 0, 0, 0, "-4")

    Timecop.freeze(today) do
      rate_estimates = @carrier.find_rates( @locations[:ottawa],
                                      @locations[:beverly_hills],
                                      @packages.values_at(:book, :wii), :test => true)

      #the above fixture will specify a transit time of 5 days, with 2 weekend days accounted for
      delivery_date = Date.today + 7
      assert_equal delivery_date, rate_estimates.rates[0].delivery_date
    end
  end

  def test_failure_to_parse_invalid_xml_results_in_a_useful_error
    mock_response = xml_fixture('fedex/invalid_fedex_reply')

    @carrier.expects(:commit).returns(mock_response)

    assert_raises ActiveMerchant::Shipping::ResponseContentError do
      rate_estimates = @carrier.find_rates(
        @locations[:ottawa],
        @locations[:beverly_hills],
        @packages.values_at(:book, :wii),
        :test => true
      )
    end
  end

end
