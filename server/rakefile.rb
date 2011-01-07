#    This file is part of EC2 on Rails.
#    http://rubyforge.org/projects/ec2onrails/
#
#    Copyright 2007 Paul Dowman, http://pauldowman.com/
#
#    EC2 on Rails is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    EC2 on Rails is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.


# This script is meant to be run by build-ec2onrails.sh, which is run by
# Eric Hammond's Ubuntu build script: http://alestic.com/
# e.g.:
# bash /mnt/ec2ubuntu-build-ami --script /mnt/ec2onrails/server/build-ec2onrails.sh ...



require "rake/clean"
require 'yaml'
require 'erb'
require "#{File.dirname(__FILE__)}/../gem/lib/ec2onrails/version"

@packages = %w(
  adduser
  apache2
  bison
  ca-certificates
  cron
  curl
  flex
  gcc
  git-core
  irb
  less
  libpcre3-dev
  libdbm-ruby
  libgdbm-ruby
  libopenssl-ruby
  libreadline-ruby
  libruby
  libssl-dev
  libxml2
  libxml2-dev
  libxslt1-dev
  libyaml-ruby
  libzlib-ruby
  libcurl4-openssl-dev
  logrotate
  make
  bsd-mailx
  memcached
  mysql-client
  mysql-server
  libmysql-ruby
  libmysqlclient-dev
  nano
  openssh-server
  postfix
  rdoc
  ri
  rsync
  ruby-full
  unzip
  vim
  wget
  monit
)

@rubygems = [
  "amazon-ec2",
  "aws-s3",
  "right_aws",
  "memcache-client",
  "mongrel",
  "mongrel_cluster",
  "optiflag",
  "rails -v 2.3.5",
  "rake"
]

@build_root = "/mnt/build"
@fs_dir = "#{@build_root}/ubuntu"

@version = [Ec2onrails::VERSION::STRING]

task :default => :configure

desc "Removes all build files"
task :clean_all => :require_root do |t|
  puts "Unmounting proc and dev from #{@build_root}..."
  run "umount #{@build_root}/ubuntu/proc", true
  run "umount #{@build_root}/ubuntu/dev", true

  puts "Removing #{@build_root}..."
  rm_rf @build_root
end

task :require_root do |t|
  if `whoami`.strip != 'root'
    raise "Sorry, this buildfile must be run as root."
  end
end

desc "Use apt-get to install required packages inside the image's filesystem"
task :install_packages => :require_root do |t|
  unless_completed(t) do
    ENV['DEBIAN_FRONTEND'] = 'noninteractive'
    ENV['LANG'] = ''
    run_chroot "apt-get update"
    run_chroot "apt-get install -y #{@packages.join(' ')}"
    run_chroot "apt-get autoremove -y"
    run_chroot "apt-get clean"
  end
end

desc "Install required ruby gems inside the image's filesystem"
task :install_gems => [:require_root, :install_packages] do |t|
  unless_completed(t) do
    version = "1.3.6"
    dir = "69365"

    filename = "rubygems-#{version}.tgz"
    url = "http://rubyforge.org/frs/download.php/#{dir}/#{filename}"
    run_chroot "sh -c 'cd /tmp && wget -q #{url} && tar zxf #{filename}'"
    run_chroot "sh -c 'cd /tmp/rubygems-#{version} && ruby setup.rb'"
    run_chroot "ln -sf /usr/bin/gem1.8 /usr/bin/gem"
    run_chroot "gem source -a http://rubygems.org"
    run_chroot "gem sources -a http://gems.github.com"
    run_chroot "gem install gemcutter --no-rdoc --no-ri"
    @rubygems.each do |g|
      run_chroot "gem install #{g} --no-rdoc --no-ri"
    end
  end
end

desc "Copy files into the image"
task :copy_files do |t|
  unless_completed(t) do
    sh("cp -r files/* #{@fs_dir}")
  end
end

desc "Set file permissions. This is needed because files stored in git don't keep their metadata"
task :set_file_permissions => :copy_files do |t|
  run_chroot "chmod -R 700 /etc/monit"
end

desc "Configure the image"
task :configure => [:require_root, :install_gems, :set_file_permissions] do |t|
  unless_completed(t) do
    replace("#{@fs_dir}/etc/motd.tail", /!!VERSION!!/, "Version #{@version}")
    
    run_chroot "a2enmod deflate"
    run_chroot "a2enmod headers"
    run_chroot "a2enmod proxy_balancer"
    run_chroot "a2enmod proxy_http"
    run_chroot "a2enmod rewrite"
    
    run_chroot "/usr/sbin/adduser --gecos ',,,' --disabled-password app"
    run_chroot "/usr/sbin/adduser --gecos ',,,' --disabled-password admin"
    run_chroot "/usr/sbin/adduser admin adm"
    run_chroot "/usr/sbin/addgroup sudoers"
    
    File.open("#{@fs_dir}/etc/init.d/ec2-get-credentials", 'a') do |f|
      f << <<-END
        mkdir -p -m 700 /home/app/.ssh
        cp /root/.ssh/authorized_keys /home/app/.ssh
        chown -R app:app /home/app/.ssh

        mkdir -p -m 700 /home/admin/.ssh
        cp /root/.ssh/authorized_keys /home/admin/.ssh
        chown -R admin:admin /home/admin/.ssh
        END
    end
    
    run "echo '. /usr/local/ec2onrails/config' >> #{@fs_dir}/root/.bashrc"
    run "echo '. /usr/local/ec2onrails/config' >> #{@fs_dir}/home/app/.bashrc"
    run "echo '. /usr/local/ec2onrails/config' >> #{@fs_dir}/home/admin/.bashrc"
    
    run_chroot "cp /root/.gemrc /home/app"
    run_chroot "cp /root/.gemrc /home/admin"
    
    %w(apache2 mysql auth.log daemon.log kern.log mail.err mail.info mail.log mail.warn syslog user.log).each do |f|
      rm_rf "#{@fs_dir}/var/log/#{f}"
      run_chroot "ln -sf /mnt/log/#{f} /var/log/#{f}"
    end
    
    # To Enable monit
    run_chroot "perl -pi -e 's/startup=0/startup=1/' /etc/default/monit"
    touch "#{@fs_dir}/ec2onrails-first-boot"
  end
end

desc "This task is for deploying the contents of /files to a running server image to test config file changes without rebuilding."
task :deploy_files do |t|
  raise "need 'key' and 'host' env vars defined" unless ENV['key'] && ENV['host']
  run "rsync -rlvzcC --rsh='ssh -l root -i #{ENV['key']}' files/ #{ENV['host']}:/"
end

##################

# Execute a given block and touch a stampfile. The block won't be run if the stampfile exists.
def unless_completed(task, &proc)
  stampfile = "#{@build_root}/#{task.name}.completed"
  unless File.exists?(stampfile)
    yield  
    touch stampfile
  end
end

def run_chroot(command, ignore_error = false)
  run "chroot '#{@fs_dir}' #{command}", ignore_error
end

def run(command, ignore_error = false)
  puts "*** #{command}" 
  result = system command
  raise("error: #{$?}") unless result || ignore_error
end

# def mount(type, mount_point)
#   unless mounted?(mount_point)
#     puts
#     puts "********** Mounting #{type} on #{mount_point}..."
#     puts
#     run "mount -t #{type} none #{mount_point}"
#   end
# end
# 
# def mounted?(mount_point)
#   mount_point_regex = mount_point.gsub(/\//, "\\/")
#   `mount`.select {|line| line.match(/#{mount_point_regex}/) }.any?
# end

def replace_line(file, newline, linenum)
  contents = File.open(file, 'r').readlines
  contents[linenum - 1] = newline
  File.open(file, 'w') do |f|
    contents.each {|line| f << line}
  end
end

def replace(file, pattern, text)
  contents = File.open(file, 'r').readlines
  contents.each do |line|
    line.gsub!(pattern, text)
  end
  File.open(file, 'w') do |f|
    contents.each {|line| f << line}
  end
end
