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

# Module:	update_proposal.ycp
#
# Author:	Arvin Schnell <arvin@suse.de>
#
# Purpose:	Let user choose update settings.
#
# $Id$
module Yast
  class UpdateProposalClient < Client
    include Yast::Logger

    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "update"

      Yast.import "HTML"
      Yast.import "Update"
      Yast.import "RootPart"
      Yast.import "Packages"
      Yast.import "PackageCallbacks"
      Yast.import "SpaceCalculation"

      Yast.import "Installation"
      Yast.import "Popup"
      Yast.import "ProductFeatures"
      Yast.import "Product"
      Yast.import "FileUtils"
      Yast.import "Label"
      Yast.import "Stage"


      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      @rpm_db_existency_checked_already = false


      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        # call some function that makes a proposal here:
        #
        # DummyMod::MakeProposal( force_reset );

        if @force_reset
          Update.Reset
          Packages.Reset([:product])
          Update.did_init1 = false
          @rpm_db_existency_checked_already = false
        end

        # bugzilla #148105
        if !@rpm_db_existency_checked_already
          @rpm_db_existency_checked_already = true

          # if it doesn't exist, user can still confirm to continue
          # packager will then suggest some set of packages
          if !CheckRPMDBforExistency()
            return {
              # error message in proposal
              "warning"       => _(
                "Cannot read the current RPM Database."
              ),
              "warning_level" => :fatal,
              "raw_proposal"  => []
            }
          end
        end

        # Fill return map

        init_stuff

        if Update.products_incompatible
          return {
            # error message in proposal
            "warning"       => _(
              "The installed product is not compatible with the product on the installation media."
            ),
            "warning_level" => :fatal,
            "raw_proposal"  => []
          }
        end

        # TRANSLATORS: unknown product (label)
        @update_from = _("Unknown product")
        if Ops.get_string(Installation.installedVersion, "show", "") != "" &&
            Ops.get_string(Installation.installedVersion, "show", "?") != "?"
          @update_from = Ops.get_string(
            Installation.installedVersion,
            "show",
            ""
          )
        elsif Ops.get_string(Installation.installedVersion, "version", "") != "" &&
            Ops.get_string(Installation.installedVersion, "version", "?") != "?"
          @update_from = Ops.get_string(
            Installation.installedVersion,
            "name",
            ""
          )
        end

        # TRANSLATORS: unknown product (label)
        @update_to = _("Unknown product")
        if Ops.get_string(Installation.updateVersion, "show", "") != ""
          @update_to = Ops.get_string(Installation.updateVersion, "show", "")
        elsif Ops.get_string(Installation.updateVersion, "version", "") != ""
          @update_to = Ops.get_string(Installation.updateVersion, "name", "")
        end

        # when versions don't match and upgrade is not allowed (running system)
        if Ops.get_string(Installation.installedVersion, "version", "A") !=
            Ops.get_string(Installation.updateVersion, "version", "B") &&
            Update.disallow_upgrade
          return {
            "warning"       => Builtins.sformat(
              # TRANSLATORS: proposal error, %1 is the version of installed system
              # %2 is the version being installed
              _(
                "Updating system to another version (%1 -> %2) is not supported on the running system.<br>\n" +
                  "Boot from the installation media and use a normal upgrade\n" +
                  "or disable software repositories of products with different versions.\n"
              ),
              @update_from,
              @update_to
            ),
            "warning_level" => :fatal,
            "raw_proposal"  => []
          }
        end

        @warning_message = nil

        # when labels don't match
        if !Stage.initial &&
            Ops.get_string(Installation.installedVersion, "show", "A") !=
              Ops.get_string(Installation.updateVersion, "show", "B")
          @warning_message = Builtins.sformat(
            # TRANSLATORS: proposal warning, both %1 and %2 are replaced with product names
            _(
              "Warning: Updating from '%1' to '%2', products do not exactly match."
            ),
            Ops.get_locale(
              # TRANSLATORS: unknown product name
              Installation.installedVersion,
              "show",
              _("Unknown product")
            ),
            Ops.get_locale(
              # TRANSLATORS: unknown product name
              Installation.updateVersion,
              "show",
              _("Unknown product")
            )
          )
        end

        # stores the proposal text output
        @summary_text = ""

        @products = Update.SelectedProducts
        @already_printed = []

        Builtins.foreach(@products) do |one_product|
          # never print duplicates, bugzilla #331560
          # 'toset' could be used but we want to keep sorting
          if Builtins.contains(@already_printed, one_product)
            next
          else
            @already_printed = Builtins.add(@already_printed, one_product)
          end
          # TRANSLATORS: proposal summary item, %1 is a product name
          @summary_text = Ops.add(
            Ops.add(
              Ops.add(@summary_text, "<li><b>"),
              Builtins.sformat(_("Update to %1"), one_product)
            ),
            "</b></li>\n"
          )
        end if @products != nil

        #	if (Update::deleteOldPackages) {
        #	    // Proposal for removing packages which are not maintained any more
        #	    summary_text = summary_text + "<li>" + _("Delete unmaintained packages") + "</li>\n";
        #	}

        if Update.onlyUpdateInstalled
          # Proposal for backup during update
          @summary_text = Ops.add(
            Ops.add(
              Ops.add(@summary_text, "<li>"),
              _("Only update installed packages")
            ),
            "</li>\n"
          )
        else
          @patterns = Pkg.ResolvableProperties("", :pattern, "")
          @patterns = Builtins.filter(@patterns) do |p|
            Ops.get(p, "status") == :selected &&
              Ops.get_boolean(p, "user_visible", true) &&
              Ops.get_string(p, "summary", Ops.get_string(p, "name", "")) != ""
          end
          # proposal string
          @summary_text = Ops.add(
            Ops.add(
              Ops.add(@summary_text, "<li>"),
              _("Update based on patterns")
            ),
            "</li>\n"
          )

          if @patterns != nil && Ops.greater_than(Builtins.size(@patterns), 0)
            @summary_text = Ops.add(@summary_text, HTML.ListStart)

            Builtins.foreach(@patterns) do |p|
              @summary_text = Ops.add(
                Ops.add(
                  Ops.add(@summary_text, "<li>"),
                  Ops.get_string(p, "summary", Ops.get_string(p, "name", ""))
                ),
                "</li>\n"
              )
            end

            @summary_text = Ops.add(@summary_text, HTML.ListEnd)
          end
        end

        # recalculate the disk space usage data
        SpaceCalculation.GetPartitionInfo

        # TRANSLATORS: proposal dialog help
        @update_options_help = _(
          "<p><b><big>Update Options</big></b> Select how your system will be updated.\n" +
            "Choose if only installed packages should be updated or new ones should be\n" +
            "installed as well (default). Decide whether unmaintained packages should be\n" +
            "deleted.</p>\n"
        )

        @ret = {
          "preformatted_proposal" => Ops.add(
            Ops.add(HTML.ListStart, @summary_text),
            HTML.ListEnd
          ),
          "help"                  => @update_options_help
        }

        if @warning_message != nil
          Ops.set(@ret, "warning", @warning_message)
          Ops.set(@ret, "warning_level", :warning)
        end
      elsif @func == "AskUser"
        @has_next = Ops.get_boolean(@param, "has_next", false)

        # call some function that displays a user dialog
        # or a sequence of dialogs here:
        #
        # sequence = DummyMod::AskUser( has_next );

        @result = Convert.to_symbol(
          WFM.CallFunction("inst_update", [true, @has_next])
        )

        Update.did_init1 = false if @result == :next

        # Fill return map

        @ret = { "workflow_sequence" => @result }
      elsif @func == "Description"
        # Fill return map.
        #
        # Static values do just nicely here, no need to call a function.

        @ret = {
          # this is a heading
          "rich_text_title" => _("Update Options"),
          # this is a menu entry
          "menu_title"      => _("&Update Options"),
          "id"              => "update_stuff"
        }
      end

      deep_copy(@ret)
    end

    # Function returns map of upgrade-configuration.
    # Some keys might be missing. In that case, the default libzypp
    # values will be used. See FATE #301990 and bnc #238488.
    # The keys should be matching keys for Pkg::PkgUpdateAll().
    # "keep_installed_patches" were removed by bnc #349533.
    #
    # @return [Hash{String => Object}] with a configuration
    #
    #
    # **Structure:**
    #
    #     $[
    #          "delete_unmaintained" : boolean,
    #          "silent_downgrades" : boolean,
    #      ]
    def GetUpdateConf
      # 'nil' values are skipped, in that case, ZYPP uses own default values
      ret = {}

      # not supported by libzypp anymore
      #	if (Update::deleteOldPackages != nil) {
      #	    ret["delete_unmaintained"] = Update::deleteOldPackages;
      #	}

      if Update.silentlyDowngradePackages != nil
        Ops.set(ret, "silent_downgrades", Update.silentlyDowngradePackages)
      end

      Builtins.y2milestone("Using update configuration: %1", ret)

      deep_copy(ret)
    end

    # bugzilla #148105
    # Check the current RPM Database if exists
    #
    # RPM DB found -> return true
    # RPM DB not found & skipped -> return true
    # RPM DB not found & aborted -> return false
    #
    def CheckRPMDBforExistency
      Builtins.y2milestone(
        "Checking the current RPM Database in '%1'...",
        Installation.destdir
      )

      # at least one must be there, the second one is for RPM v3
      rpm_db_files = ["/var/lib/rpm/Packages", "/var/lib/rpm/packages.rpm"]
      ret = false
      file_found_or_error_skipped = false

      while !file_found_or_error_skipped
        Builtins.foreach(rpm_db_files) do |check_file|
          if Installation.destdir != "/"
            check_file = Builtins.sformat(
              "%1%2",
              Installation.destdir,
              check_file
            )
          end
          if FileUtils.Exists(check_file)
            Builtins.y2milestone("RPM Database '%1' found", check_file)
            ret = true
            file_found_or_error_skipped = true
            raise Break
          end
        end

        # file not found
        if !ret
          Builtins.y2error(
            "None of files %1 exist in '%2'",
            rpm_db_files,
            Installation.destdir
          )

          missing_files = ""
          Builtins.foreach(rpm_db_files) do |check_file|
            if Installation.destdir != "/"
              check_file = Builtins.sformat(
                "%1%2",
                Installation.destdir,
                check_file
              )
            end
            missing_files = Ops.add(Ops.add(missing_files, "\n"), check_file)
          end

          UI.OpenDialog(
            Opt(:decorated),
            VBox(
              # popup error
              Label(
                Ops.add(
                  Ops.add(
                    # part of error popup message
                    _("Cannot read the current RPM Database.") + "\n\n",
                    # part of error popup message, %1 stands for newline-separated list of files
                    Builtins.sformat(
                      _("None of these files exist:%1"),
                      missing_files
                    )
                  ),
                  "\n\n"
                )
              ),
              HBox(
                PushButton(Id(:abort), Label.AbortButton), # disabled button - bugzilla #148105, comments #22 - #28
                # `PushButton (`id(`ignore), Label::IgnoreButton())
                PushButton(Id(:retry), Label.RetryButton)
              )
            )
          )

          ui_r = UI.UserInput

          if ui_r == :cancel || ui_r == :abort
            ret = false
            file_found_or_error_skipped = true
            Builtins.y2milestone("Check failed, returning error.")
          elsif ui_r == :retry
            file_found_or_error_skipped = false
            Builtins.y2milestone("Trying again...") 
            #} else if (ui_r == `ignore) {
            #    ret = true;
            #    file_found_or_error_skipped = true;
            #    y2warning ("Skipping missing RPM Database, problems might occur...");
          else
            file_found_or_error_skipped = false
            Builtins.y2error("Unexpected return: %1", ui_r)
          end

          UI.CloseDialog
        end
      end

      Builtins.y2milestone("CheckRPMDBforExistency - returning: %1", ret)
      ret
    end

    def init_stuff
      # initialize package manager
      Packages.Init(true)

      # initialize target
      if true
        PackageCallbacks.SetConvertDBCallbacks

        Pkg.TargetInit(Installation.destdir, false)

        Update.GetProductName
      end

      # FATE #301990, Bugzilla #238488
      # Set initial update-related (packages/patches) values from control file
      Update.InitUpdate

      # some products are listed in media control file and at least one is compatible
      # with system just being updated
      update_not_possible = false

      # FATE #301844
      Builtins.y2milestone(
        "Previous '%1', New '%2' RootPart",
        RootPart.previousRootPartition,
        RootPart.selectedRootPartition
      )
      if RootPart.previousRootPartition != RootPart.selectedRootPartition
        RootPart.previousRootPartition = RootPart.selectedRootPartition

        # check whether update is possible
        # reset deleteOldPackages and onlyUpdateInstalled in respect to the selected system
        Update.Reset
        if !Update.IsProductSupportedForUpgrade
          Builtins.y2milestone("Upgrade is not supported")
          update_not_possible = true
        end
      end

      # connect target with package manager
      if !Update.did_init1
        Update.did_init1 = true

        restore = []
        selected = Pkg.ResolvableProperties("", :product, "")
        Builtins.foreach(selected) do |s|
          restore = Builtins.add(restore, Ops.get_string(s, "name", ""))
        end

        Pkg.PkgApplReset

        # bnc #300540
        # bnc #391785
        # Drops packages after PkgApplReset, not before (that would null that)
        Update.DropObsoletePackages

        Builtins.foreach(restore) { |res| Pkg.ResolvableInstall(res, :product) }
        Update.SetDesktopPattern if !Update.onlyUpdateInstalled

        if !Update.OnlyUpdateInstalled
          Packages.default_patterns.each do |pattern|
            select_pattern_result = Pkg.ResolvableInstall(pattern, :pattern)
            log.info "Pre-select pattern #{pattern}: #{select_pattern_result}"
          end
        end

        Packages.SelectProduct

        # FATE #301990, Bugzilla #238488
        # Control the upgrade process better
        update_sum = Pkg.PkgUpdateAll(GetUpdateConf())
        Builtins.y2milestone("Update summary: %1", update_sum)
        Update.unknown_packages = Ops.get(update_sum, :ProblemListSze, 0)

        sys_patterns = Packages.ComputeSystemPatternList
        Builtins.foreach(sys_patterns) do |pat|
          Pkg.ResolvableInstall(pat, :pattern)
        end

        if Pkg.PkgSolve(!Update.onlyUpdateInstalled)
          Update.solve_errors = 0
        else
          Update.solve_errors = Pkg.PkgSolveErrors
        end
      end
      # check product compatibility
      if !(Update.ProductsCompatible || Update.products_incompatible) || update_not_possible
        if Popup.ContinueCancel(
            # continue-cancel popup
            _(
              "The installed product is not compatible with the product\n" +
                "on the installation media. If you try to update using the\n" +
                "current installation media, the system may not start or\n" +
                "some applications may not run properly."
            )
          )
          Update.IgnoreProductCompatibility
        else
          Update.products_incompatible = true
        end
      end

      nil
    end
  end
end

Yast::UpdateProposalClient.new.main
