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
require "yast/ui_shortcuts"

Yast.import "UI"

module Y2Update
  module Widget
    class ProgressBarHandler
      include Yast::UIShortcuts

      def initialize(message)
        @message = message
      end

      def show
        return unless exist?

        Yast::UI.ReplaceWidget(
          Id("search_progress"),
          ProgressBar(
            Id("search_pb"),
            message,
            100,
            0
          )
        )
      end

      def update(total, current)
        return unless exist?

        percent = 100 * (current + 1 / total)
        Yast::UI.ChangeWidget(Id("search_pb"), :Value, percent)
      end

      # 100%
      def complete
        return unless exist?

        Yast::UI.ChangeWidget(Id("search_pb"), :Value, 100)
      end

    private

      attr_reader :message

      def exist?
        Yast::UI.WidgetExists(Id("search_progress"))
      end
    end
  end
end