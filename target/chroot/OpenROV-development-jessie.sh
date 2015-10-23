#!/bin/sh -e
#
# Copyright (c) 2014 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

u_boot_release="v2015.10-rc3"
u_boot_release_x15="v2015.07"
#bone101_git_sha="50e01966e438ddc43b9177ad4e119e5274a0130d"

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

echo "env: [`env`]"

curl http://127.0.0.1:3000 > /dev/null || true
if [ "$?" eq "0" ] ; then
	export HTTP_PROXY=http://127.0.0.1:3000
	export HTTPS_PROXY=http://127.0.0.1:3000
fi

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

cleanup_npm_cache () {
	if [ -d /root/tmp/ ] ; then
		rm -rf /root/tmp/ || true
	fi

	if [ -d /root/.npm ] ; then
		rm -rf /root/.npm || true
	fi
}

install_node_pkgs () {
	if [ -f /usr/bin/npm ] ; then
		cd /
		echo "Installing npm packages"
		echo "debug: node: [`node --version`]"
		echo "debug: npm: [`npm --version`]"

		echo "NODE_PATH=/usr/local/lib/node_modules" > /etc/default/node
		echo "export NODE_PATH=/usr/local/lib/node_modules" > /etc/profile.d/node.sh
		chmod 755 /etc/profile.d/node.sh

		#debug
		#echo "debug: npm config ls -l (before)"
		#echo "--------------------------------"
		#npm config ls -l
		#echo "--------------------------------"

		#c9-core-installer...
		npm config delete cache
		npm config delete tmp
		npm config delete python

		#fix npm in chroot.. (did i mention i hate npm...)
		if [ ! -d /root/.npm ] ; then
			mkdir -p /root/.npm
		fi
		npm config set cache /root/.npm
		npm config set group 0
		npm config set init-module /root/.npm-init.js

		if [ ! -d /root/tmp ] ; then
			mkdir -p /root/tmp
		fi
		npm config set tmp /root/tmp
		npm config set user 0
		npm config set userconfig /root/.npmrc

		if [ -f /usr/bin/make ] ; then
			echo "Installing: [npm install -g bonescript@0.2.5]"
			TERM=dumb npm install -g bonescript@0.2.5
		fi

		git_repo="https://github.com/openrov/openrov-cockpit"
		git_target_dir="/opt/openrov/cockpit"
		git_clone_full
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			TERM=dumb npm install
			cd src/static
			TERM=dumb npm install
			TERM=dumb npm run bower
			cd ../..


			wfile="/lib/systemd/system/orov-cockpit.socket"
			echo "[Socket]" > ${wfile}
			echo "ListenStream=8080" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Install]" >> ${wfile}
			echo "WantedBy=sockets.target" >> ${wfile}

			wfile="/lib/systemd/system/orov-cockpit.service"
			echo "[Unit]" > ${wfile}
			echo "Description=Cockpit server" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Service]" >> ${wfile}
			#http://stackoverflow.com/questions/22498753/no-data-from-socket-activation-with-systemd
			echo "NonBlocking=True" >> ${wfile}
			echo "WorkingDirectory=/opt/openrov/cockpit/src" >> ${wfile}
			echo "ExecStart=/usr/bin/node cockpit.js" >> ${wfile}
			echo "SyslogIdentifier=orov-cockpit" >> ${wfile}

			systemctl enable orov-cockpit.socket || true

			bash install_lib/openrov-cockpit-afterinstall.sh
		fi

		git_repo="https://github.com/openrov/openrov-dashboard"
		git_target_dir="/opt/openrov/dashboard"
		git_clone_full
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			TERM=dumb npm install
			TERM=dumb npm run-script bower
			wfile="/lib/systemd/system/orov-dashboard.socket"
			echo "[Socket]" > ${wfile}
			echo "ListenStream=3080" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Install]" >> ${wfile}
			echo "WantedBy=sockets.target" >> ${wfile}

			wfile="/lib/systemd/system/orov-dashboard.service"
			echo "[Unit]" > ${wfile}
			echo "Description=Cockpit server" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Service]" >> ${wfile}
			#http://stackoverflow.com/questions/22498753/no-data-from-socket-activation-with-systemd
			echo "NonBlocking=True" >> ${wfile}
			echo "WorkingDirectory=/opt/openrov/dashboard/src" >> ${wfile}
			echo "ExecStart=/usr/bin/node dashboard.js" >> ${wfile}
			echo "SyslogIdentifier=orov-dashboard" >> ${wfile}

			systemctl enable orov-dashboard.socket || true

		fi

		git_repo="https://github.com/openrov/openrov-proxy"
		git_target_dir="/opt/openrov/openrov-proxy"
		git_clone_full
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			TERM=dumb npm install
			cd proxy-via-browser
			TERM=dumb npm install
			cd ${git_target_dir}/
			ln -s /opt/openrov/openrov-proxy/proxy-via-browser/ /opt/openrov/proxy
			bash install_lib/openrov-proxy-afterinstall.sh
		fi


		echo "Installing wetty"
		TERM=dumb npm install -g wetty

		echo "Installing ungit"
		TERM=dumb npm install -g ungit


		cd /opt/

		#cloud9 installed by cloud9-installer
		if [ -d /opt/cloud9/build/standalonebuild ] ; then
			if [ -f /usr/bin/make ] ; then
				echo "Installing winston"
				TERM=dumb npm install -g winston --arch=armhf
			fi

			#cloud9 conflicts with the openrov proxy, move cloud 9
			if [ -f //lib/systemd/system/cloud9.socket ] ; then
				sed -i -e 's:3000:3131:g' /lib/systemd/system/cloud9.socket
			fi

			systemctl enable cloud9.socket || true
			systemctl start cloud9.socket || true
		fi

		cleanup_npm_cache
		sync
    cd /
	fi
}

install_git_repos () {

	git_repo="https://github.com/openrov/openrov-software-arduino"
	git_target_dir="/opt/openrov/arduino"
	git_clone

	git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
	git_branch="4.1-ti"
	git_target_dir="/opt/source/dtb-${git_branch}"
	git_clone_branch

	git_repo="https://github.com/beagleboard/bb.org-overlays"
	git_target_dir="/opt/source/bb.org-overlays"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ ! "x${repo_rcnee_pkg_version}" = "x" ] ; then
			is_kernel=$(echo ${repo_rcnee_pkg_version} | grep 4.1)
			if [ ! "x${is_kernel}" = "x" ] ; then
				if [ -f /usr/bin/make ] ; then
					./dtc-overlay.sh
					make
					make install
					update-initramfs -u -k ${repo_rcnee_pkg_version}
					rm -rf /home/${rfs_username}/git/ || true
					make clean
				fi
			fi
		fi
		cd /
	fi

	git_repo="https://github.com/openrov/openrov-image-customization"
	git_target_dir="/opt/openrov/image-customization"
	git_branch="jessie"
	git_clone_branch
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		./afterinstall.sh || true
	fi

}

todo () {
	#Setup nginx
	cd /etc/nginx/sites-enabled/
	cp /opt/openrov/image-customization/nginx/default default
}


is_this_qemu

#setup_system
#setup_desktop

#install_gem_pkgs
install_node_pkgs
#install_pip_pkgs
if [ -f /usr/bin/git ] ; then
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
fi
#install_build_pkgs
#other_source_links
#unsecure_root
#todo
