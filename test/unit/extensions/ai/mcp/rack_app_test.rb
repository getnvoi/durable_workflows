# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class MCPRackAppTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_call_returns_rack_response
    mock_server = Object.new
    mock_server.define_singleton_method(:handle_json) { |_request| '{"result":"ok"}' }

    app = AI::MCP::RackApp.new(mock_server)

    env = {
      "REQUEST_METHOD" => "POST",
      "rack.input" => StringIO.new('{"method":"test"}'),
      "CONTENT_TYPE" => "application/json",
      "QUERY_STRING" => "",
      "PATH_INFO" => "/"
    }

    status, headers, body = app.call(env)

    assert_equal 200, status
    assert_equal "application/json", headers["Content-Type"]
    assert_includes body.first, "result"
  end

  def test_call_handles_get_request
    mock_server = Object.new

    app = AI::MCP::RackApp.new(mock_server)

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/health",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new("")
    }

    status, _headers, body = app.call(env)

    # SSE not implemented
    assert_equal 501, status
  end

  def test_call_handles_invalid_json
    mock_server = Object.new
    mock_server.define_singleton_method(:handle_json) { |body|
      JSON.parse(body)  # This will raise
    }

    app = AI::MCP::RackApp.new(mock_server)

    env = {
      "REQUEST_METHOD" => "POST",
      "rack.input" => StringIO.new("not valid json"),
      "CONTENT_TYPE" => "application/json",
      "QUERY_STRING" => "",
      "PATH_INFO" => "/"
    }

    status, _headers, body = app.call(env)

    assert_equal 400, status
    assert_includes body.first, "error"
  end

  def test_call_handles_server_error
    mock_server = Object.new
    mock_server.define_singleton_method(:handle_json) { |_| raise "Server error" }

    app = AI::MCP::RackApp.new(mock_server)

    env = {
      "REQUEST_METHOD" => "POST",
      "rack.input" => StringIO.new('{"method":"test"}'),
      "CONTENT_TYPE" => "application/json",
      "QUERY_STRING" => "",
      "PATH_INFO" => "/"
    }

    status, _headers, body = app.call(env)

    assert_equal 400, status
    assert_includes body.first, "error"
  end

  def test_call_handles_delete
    mock_server = Object.new

    app = AI::MCP::RackApp.new(mock_server)

    env = {
      "REQUEST_METHOD" => "DELETE",
      "PATH_INFO" => "/session",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new("")
    }

    status, _headers, _body = app.call(env)

    assert_equal 200, status
  end

  def test_call_handles_unsupported_method
    mock_server = Object.new

    app = AI::MCP::RackApp.new(mock_server)

    env = {
      "REQUEST_METHOD" => "PUT",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new("")
    }

    status, _headers, body = app.call(env)

    assert_equal 405, status
    assert_includes body.first, "not allowed"
  end
end
