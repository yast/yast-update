# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# Module:  SUSERelease.rb
#
# Authors: Lukas Ocilka <locilka@suse.cz>
#
# Purpose: Provides access to information provided by /etc/SuSE-release.
#          Only for backward-compatibility during upgrade - it has been
#          replaced by /etc/os-release handled by OSRelease module.
#
require "yast"

module Yast
  class SUSEReleaseFileMissingError < StandardError
    def initialize(message)
      super message
    end
  end

  class SUSEReleaseClass < Module
    include Yast::Logger

    RELEASE_FILE_PATH = "/etc/SuSE-release".freeze

    def initialize
      textdomain "update"

      Yast.import "FileUtils"
    end

    # Returns product name as found in SuSE-release file.
    # Compatible with OSRelease.ReleaseInformation.
    # Returns SUSEReleaseFileMissingError if SuSE-release file is missing.
    # Returns IOError is SuSE-release could not be open.
    #
    # @param [String] system base-directory, default is "/"
    # @return [String] product name
    def ReleaseInformation(base_dir = "/")
      release_file = File.join(base_dir, RELEASE_FILE_PATH)

      if !FileUtils.Exists(release_file)
        log.info "Release file #{release_file} not found"
        raise(
          SUSEReleaseFileMissingError,
          # TRANSLATORS: error message, %{file} is replaced with file name
          format(_("Release file %{file} not found"), file: release_file)
        )
      end

      file_contents = SCR.Read(path(".target.string"), release_file)
      if file_contents.nil?
        log.error "Cannot read file #{release_file}"
        raise(
          IOError,
          # TRANSLATORS: error message, %{file} is replaced with file name
          format(_("Cannot read release file %{file}"), file: release_file)
        )
      end

      product_name = file_contents.split(/\n/)[0]
      shorten(product_name)
    end

    # Removes all unneeded stuff such as architecture or product nickname
    def shorten(long_name)
      long_name.gsub(/ *\(.*/, "")
    end

    publish function: :ReleaseInformation, type: "string (string)"
  end

  SUSERelease = SUSEReleaseClass.new
end
