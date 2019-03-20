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
require "yast/i18n"
require "yast/ui_shortcuts"

Yast.import "UI"

module Y2Update
  module Dialog
    class GenericQuestion
      include Yast::I18n
      include Yast::UIShortcuts

      # @param [String] headline (optional; to disable, use "")
      # @param [String] question
      # @param string button (true)
      # @param string button (false)
      # @param [String] details (hidden under [Details] button; optional; to disable, use "")
      def initialize(headline, question, button_yes, button_no, details)
        textdomain "update"

        @headline = headline
        @question = question
        @button_yes = button_yes
        @button_no = button_no
        @details = details
      end

      # @return [Boolean]
      def run
        has_details = true
        has_details = false if details == "" || details == nil

        has_heading = true
        has_heading = false if headline == "" || headline == nil

        heading = has_heading ? VBox(Left(Heading(headline))) : Empty()

        popup_def = Left(Label(question))

        details_checkbox = has_details ?
          VBox(
            VSpacing(1),
            Left(CheckBox(Id(:details), Opt(:notify), _("Show &Details"), false))
          ) :
          Empty()

        popup_buttons = VBox(
          VSpacing(1),
          HBox(
            HSpacing(8),
            PushButton(Id(:yes), button_yes),
            VSpacing(2),
            PushButton(Id(:cancel), button_no),
            HSpacing(8)
          ),
          VSpacing(0.5)
        )

        UI.OpenDialog(
          Opt(:decorated),
          VSquash(
            VBox(
              heading,
              popup_def,
              Left(Opt(:hstretch), ReplacePoint(Id(:rp_details), Empty())),
              details_checkbox,
              popup_buttons
            )
          )
        )
        UI.SetFocus(Id(:yes))

        userinput = nil
        ret = nil

        while true
          userinput = UI.UserInput

          if userinput == :yes
            ret = true
            break
          elsif userinput == :details
            curr_status = Convert.to_boolean(UI.QueryWidget(Id(:details), :Value))

            if curr_status == false
              UI.ReplaceWidget(Id(:rp_details), Empty())
            else
              UI.ReplaceWidget(
                Id(:rp_details),
                MinSize(
                  60,
                  10,
                  RichText(Id(:details_text), Opt(:plainText, :hstretch), details)
                )
              )
            end
          else
            ret = false
            break
          end
        end

        UI.CloseDialog

        ret
      end

    private

      attr_reader :headline

      attr_reader :question

      attr_reader :button_yes

      attr_reader :button_no

      attr_reader :details
    end
  end
end
