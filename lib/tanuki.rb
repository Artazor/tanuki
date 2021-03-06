libdir = File.dirname(__FILE__)
$:.unshift(libdir) unless $:.include?(libdir)

require 'active_support/all'
require 'rack'
require 'fileutils'
require 'sequel'
require 'yaml'
require 'escape_utils'
require 'escape_utils/url/rack'
require 'tanuki/version'
require 'tanuki/extensions/module'
require 'tanuki/extensions/object'
require 'tanuki/extensions/rack/builder'
require 'tanuki/extensions/rack/server'
require 'tanuki/extensions/rack/static_dir'
require 'tanuki/behavior/controller_behavior'
require 'tanuki/behavior/meta_model_behavior'
require 'tanuki/behavior/model_behavior'
require 'tanuki/behavior/object_behavior'
require 'tanuki/argument'
require 'tanuki/configurator'
require 'tanuki/context'
require 'tanuki/launcher'
require 'tanuki/loader'
require 'tanuki/i18n'
require 'tanuki/template_compiler'
require 'tanuki/application'

module Tanuki
end