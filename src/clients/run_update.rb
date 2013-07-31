# encoding: utf-8

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

# File:	clients/update.ycp
# Module:	System update
# Summary:	Update client that actually does the update
#		it's called from ypdate.ycp
# Authors:	Klaus Kaempf <kkaempf@suse.de>
#		Arvin Schnell <arvin@suse.de>
#		Lukas Ocilka <locilka@suse.cz>
#
# $Id$
module Yast
  class RunUpdateClient < Client
    def main
      Yast.import "Pkg"
      textdomain "update"

      Yast.import "PackageLock"
      Yast.import "Mode"
      Yast.import "ProductControl"
      Yast.import "Wizard"
      Yast.import "Update"
      Yast.import "Installation"

      # check whether having the packager for ourselves
      return :abort if !PackageLock.Check

      # set normal mode and update
      Mode.SetMode("update")

      Update.disallow_upgrade = true
      Update.onlyUpdateInstalled = true
      #    Update::deleteOldPackages = false;

      ProductControl.custom_control_file = "/usr/share/YaST2/control/update.xml"

      Wizard.OpenNextBackStepsDialog
      Wizard.SetNextButton(:next, _("&Update"))
      if !ProductControl.Init
        Builtins.y2error(
          "control file %1 not found",
          ProductControl.custom_control_file
        )
      end
      @stage_mode = [{ "stage" => "normal", "mode" => Mode.mode }]
      ProductControl.AddWizardSteps(@stage_mode)

      # bnc #394662
      # initialize target ASAP
      Pkg.TargetInit(Installation.destdir, true)

      @ret = ProductControl.Run

      Wizard.CloseDialog

      :next
    end
  end
end

Yast::RunUpdateClient.new.main
