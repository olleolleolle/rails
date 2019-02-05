# frozen_string_literal: true

require "abstract_unit"

class ViewLoadPathsTest < ActionController::TestCase
  class TestController < ActionController::Base
    def self.controller_path() "test" end

    before_action :add_view_path, only: :hello_world_at_request_time

    def hello_world() end
    def hello_world_at_request_time() render(action: "hello_world") end

    private
      def add_view_path
        prepend_view_path "#{FIXTURE_LOAD_PATH}/override"
      end
  end

  module Test
    class SubController < ActionController::Base
      layout "test/sub"
      def hello_world; render(template: "test/hello_world"); end
    end
  end

  with_routes do
    get :hello_world, to: "test#hello_world"
    get :hello_world_at_request_time, to: "test#hello_world_at_request_time"
  end

  def setup
    @controller = TestController.new
    @request  = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.new
    @paths = TestController.view_paths
    super
  end

  def teardown
    TestController.view_paths = @paths
  end

  def expand(array)
    array.map { |x| File.expand_path(x.to_s) }
  end

  def assert_paths(*paths)
    controller = paths.first.is_a?(Class) ? paths.shift : @controller
    assert_equal expand(paths), controller.view_paths.map(&:to_s)
  end

  def test_template_load_path_was_set_correctly
    assert_paths FIXTURE_LOAD_PATH
  end

  def test_controller_appends_view_path_correctly
    @controller.append_view_path "foo"
    assert_paths(FIXTURE_LOAD_PATH, "foo")

    @controller.append_view_path(%w(bar baz))
    assert_paths(FIXTURE_LOAD_PATH, "foo", "bar", "baz")

    @controller.append_view_path(FIXTURE_LOAD_PATH)
    assert_paths(FIXTURE_LOAD_PATH, "foo", "bar", "baz", FIXTURE_LOAD_PATH)
  end

  def test_controller_prepends_view_path_correctly
    @controller.prepend_view_path "baz"
    assert_paths("baz", FIXTURE_LOAD_PATH)

    @controller.prepend_view_path(%w(foo bar))
    assert_paths "foo", "bar", "baz", FIXTURE_LOAD_PATH

    @controller.prepend_view_path(FIXTURE_LOAD_PATH)
    assert_paths FIXTURE_LOAD_PATH, "foo", "bar", "baz", FIXTURE_LOAD_PATH
  end

  def test_template_appends_view_path_correctly
    @controller.instance_variable_set :@template, ActionView::Base.with_view_paths(TestController.view_paths, {}, @controller)
    class_view_paths = TestController.view_paths

    @controller.append_view_path "foo"
    assert_paths FIXTURE_LOAD_PATH, "foo"

    @controller.append_view_path(%w(bar baz))
    assert_paths FIXTURE_LOAD_PATH, "foo", "bar", "baz"
    assert_paths TestController, *class_view_paths
  end

  def test_template_prepends_view_path_correctly
    @controller.instance_variable_set :@template, ActionView::Base.with_view_paths(TestController.view_paths, {}, @controller)
    class_view_paths = TestController.view_paths

    @controller.prepend_view_path "baz"
    assert_paths "baz", FIXTURE_LOAD_PATH

    @controller.prepend_view_path(%w(foo bar))
    assert_paths "foo", "bar", "baz", FIXTURE_LOAD_PATH
    assert_paths TestController, *class_view_paths
  end

  def test_view_paths
    get :hello_world
    assert_response :success
    assert_equal "Hello world!", @response.body
  end

  def test_view_paths_override
    TestController.prepend_view_path "#{FIXTURE_LOAD_PATH}/override"
    get :hello_world
    assert_response :success
    assert_equal "Hello overridden world!", @response.body
  end

  def test_view_paths_override_for_layouts_in_controllers_with_a_module
    @controller = Test::SubController.new
    with_routes do
      get :hello_world, to: "view_load_paths_test/test/sub#hello_world"
    end

    Test::SubController.view_paths = [ "#{FIXTURE_LOAD_PATH}/override", FIXTURE_LOAD_PATH, "#{FIXTURE_LOAD_PATH}/override2" ]
    get :hello_world
    assert_response :success
    assert_equal "layout: Hello overridden world!", @response.body
  end

  def test_view_paths_override_at_request_time
    get :hello_world_at_request_time
    assert_response :success
    assert_equal "Hello overridden world!", @response.body
  end

  def test_decorate_view_paths_with_custom_resolver
    decorator_class = Class.new(ActionView::PathResolver) do
      def initialize(path_set)
        @path_set = path_set
      end

      def find_all(*args)
        @path_set.find_all(*args).collect do |template|
          ::ActionView::Template.new(
            "Decorated body",
            template.identifier,
            template.handler,
              virtual_path: template.virtual_path,
              locals: [],
              format: template.formats
          )
        end
      end
    end

    decorator = decorator_class.new(TestController.view_paths)
    TestController.view_paths = ActionView::PathSet.new.push(decorator)

    get :hello_world
    assert_response :success
    assert_equal "Decorated body", @response.body
  end

  def test_inheritance
    original_load_paths = ActionController::Base.view_paths

    self.class.class_eval %{
      class A < ActionController::Base; end
      class B < A; end
      class C < ActionController::Base; end
    }

    A.view_paths = ["a/path"]

    assert_paths A, "a/path"
    assert_paths A, *B.view_paths
    assert_paths C, *original_load_paths

    C.view_paths = []
    assert_nothing_raised { C.append_view_path "c/path" }
    assert_paths C, "c/path"
  end

  def test_lookup_context_accessor
    assert_equal ["test"], TestController.new.lookup_context.prefixes
  end
end
