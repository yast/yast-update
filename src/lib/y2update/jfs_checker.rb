# encoding: utf-8

# Copyright (c) [2019] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "yast2/execute"

module Y2Update
  class JFSChecker
    def initialize(filesystem)
      @filesystem = filesystem
    end

    def valid?
      check unless checked?

      !error?
    end

    def error?
      check unless checked?

      !error.nil?
    end

    def error_message(stdout: false)
      check unless checked?

      return nil unless error?

      return error.stderr if !stdout || error.stdout.empty?

      "#{error.stdout}\n#{error.stderr}"
    end

  private

    attr_reader :error

    def checked?
      !!@checked
    end

    def device
      filesystem.blk_devices.first
    end

    def check
      @checked = true

      Yast::Execute.locally!("fsck.jfs", "-n", device)
    rescue Cheetah::ExecutionFailed => e
      @error = e
    end
  end
end
