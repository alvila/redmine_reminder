# redMine - project management software
# Copyright (C) 2008  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

desc <<-END_DESC
Send reminders about issues due in the next days.

Available options:
  * days     => number of days to remind about (defaults to 7)
  * tracker  => id of tracker (defaults to all trackers)
  * project  => id or identifier of project (defaults to all projects)

Example:
  rake redmine:send_reminders days=7 RAILS_ENV="production"
END_DESC
require File.expand_path(File.dirname(__FILE__) + "/../../../../../config/environment")
require "mailer"
#require "actionmailer"

class Reminder_all < Mailer
  def reminder_all(user, assigned_issues, auth_issues, watched_issues, days)
    set_language_if_valid user.language
    recipients user.mail
    day_tag=[l(:mail_reminder_all_day1),l(:mail_reminder_all_day2),l(:mail_reminder_all_day2),l(:mail_reminder_all_day2),l(:mail_reminder_all_day5)]
    case (assigned_issues+auth_issues+watched_issues).uniq.size
	when 1 then subject l(:mail_subject_reminder_all1, :count => ((assigned_issues+auth_issues+watched_issues).uniq.size), :days => days, :day=>day_tag[days>4 ? 4 : days-1])
	when 2..4 then subject l(:mail_subject_reminder_all2, :count => ((assigned_issues+auth_issues+watched_issues).uniq.size), :days => days, :day=>day_tag[days>4 ? 4 : days-1])
	else subject l(:mail_subject_reminder_all5, :count => ((assigned_issues+auth_issues+watched_issues).uniq.size), :days => days, :day=>day_tag[days>4 ? 4 : days-1])
    end
    body :assigned_issues => assigned_issues,
	 :auth_issues => auth_issues,
	 :watched_issues => watched_issues,
         :days => days,
         :issues_url => url_for(:controller => 'issues', :action => 'index', :set_filter => 1, :assigned_to_id => user.id, :sort_key => 'due_date', :sort_order => 'asc')
    render_multipart('reminder_all', body)
  end
  def self.reminders_all(options={})
    days = options[:days] || 7
    project = options[:project] ? Project.find(options[:project]) : nil
    tracker = options[:tracker] ? Tracker.find(options[:tracker]) : nil

    s = ARCondition.new ["#{IssueStatus.table_name}.is_closed = ? AND #{Issue.table_name}.due_date <= ?", false, days.day.from_now.to_date]
    s << "#{Issue.table_name}.assigned_to_id IS NOT NULL"
    s << "#{Project.table_name}.status = #{Project::STATUS_ACTIVE}"
    s << "#{Issue.table_name}.project_id = #{project.id}" if project
    s << "#{Issue.table_name}.tracker_id = #{tracker.id}" if tracker
    over_due = Array.new
    issues_by_assignee = Issue.find(:all, :include => [:status, :assigned_to, :project, :tracker],
                                          :conditions => s.conditions
                                    ).group_by(&:assigned_to)
    issues_by_assignee.each do |assignee, issues|
      found=0
      over_due.each do |person|
	if person[0].mail == assignee.mail && person[1]=="assignee" then
	  person << issues
	  found=1
	end
      end
      if found==0 then
	over_due<<[assignee, "assignee", issues]
      end
    end
    s = ARCondition.new ["#{IssueStatus.table_name}.is_closed = ? AND #{Issue.table_name}.due_date <= ?", false, days.day.from_now.to_date]
    s << "#{Project.table_name}.status = #{Project::STATUS_ACTIVE}"
    s << "#{Issue.table_name}.project_id = #{project.id}" if project
    s << "#{Issue.table_name}.tracker_id = #{tracker.id}" if tracker

    issues_by = Issue.find(:all, :include => [:status, :author, :project, :watchers , :tracker],
                                          :conditions => s.conditions
                                    )
    issues_by.group_by(&:author).each do |author, issues|
      found=0
      over_due.each do |person|
	if person[0].mail == author.mail && person[1]=="author" then
	  person << issues
	  found=1
	end
      end
      if found==0 then
	over_due<<[author, "author", issues]
      end
    end
    issues_by.group_by(&:watchers).each do |watchers, issues|
      found_watchers = Array.new
      over_due.each do |person|
	watchers.each do |watcher|
	  if person[0].mail == watcher.user.mail && person[1]=="watcher" then
	    found_watchers << watcher
	    person[2] += issues
	  end
	end
      end
      watchers = watchers - found_watchers
      watchers.each do |watcher|
	over_due<<[watcher.user, "watcher", issues]
      end
    end
    over_due.sort!{|x,y| x[0].mail+x[1] <=> y[0].mail+y[1]}
    previous_user = over_due[0][0]
    watched_tasks = Array.new
    auth_tasks = Array.new
    assigned_tasks = Array.new
    sent_issues = Array.new
    over_due.each do |user, type, issues|
      sent_issues.each do |issue|
        issues-=[issue]
      end
      if previous_user == user then
	if type == "assignee" then
	  assigned_tasks += issues
	  sent_issues += issues
	elsif type == "author" then
	  auth_tasks += issues
	  sent_issues += issues
	elsif type == "watcher" then
	  watched_tasks += issues
	  sent_issues += issues
	end	
      else
	if assigned_tasks.length > 0 then
		assigned_tasks.sort! {|a,b| b.due_date <=> a.due_date }
	end
	if auth_tasks.length > 0 then
		auth_tasks.sort! {|a,b| b.due_date <=> a.due_date }
	end
	if watched_tasks.length > 0 then
		watched_tasks.sort! {|a,b| b.due_date <=> a.due_date }
	end
	deliver_reminder_all(previous_user, assigned_tasks, auth_tasks, watched_tasks, days) unless previous_user.nil?
	watched_tasks.clear
	auth_tasks.clear
	assigned_tasks.clear
	sent_issues.clear
	previous_user=user
	if type == "assignee" then
	  assigned_tasks += issues
	  sent_issues += issues
	elsif type == "author" then
	  auth_tasks += issues
	  sent_issues += issues
	elsif type == "watcher" then
	  watched_tasks += issues
	  sent_issues += issues
	end
      end
    end
    deliver_reminder_all(previous_user, assigned_tasks, auth_tasks, watched_tasks, days) unless previous_user.nil?
  end
end

namespace :redmine do
  task :send_reminders_all => :environment do
    options = {}
    options[:days] = ENV['days'].to_i if ENV['days']
    options[:project] = ENV['project'] if ENV['project']
    options[:tracker] = ENV['tracker'].to_i if ENV['tracker']

    Reminder_all.reminders_all(options)
  end
end
