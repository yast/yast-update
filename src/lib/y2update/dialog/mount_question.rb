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
require "y2update/dialog/generic_question"

module Y2Update
  module Dialog
    class MountQuestion < GenericQuestion

      def initialize(device_name, details)
        textdomain "update"

        @device_name = device_name
        @details = details
      end

    private

      attr_reader :device_name

      def headline
        _("File System Check Failed")
      end

      def question
        format(
          _(
            "The file system check of device %{device} has failed.\n\n" \
            "Do you want to continue mounting the device?\n"
          ),
          device: device_name
        )
      end

      def button_yes
        Label.ContinueButton
      end

      def button_no
        _("&Skip Mounting")
      end
    end
  end
end
