#!/bin/bash
#############################################################################################################################################
# We often find ourselves wanting to know, 'How secure is ... *secure*?' You can search stackoverflow and slashdot wondering what truecrypt #
# encryption algorithm is the most secure or best for our needs, but you find a lot of 'qualitative' answers. Users say 'Meh, AES is secure #
# enough for whatever *YOU`RE* doing, the more complex algorithms (such as the cascading methods) will really 'bog your system down'.       #
#																	    #
# I shouldn`t need to point out that the other users really have no idea what we need encryption for, THAT`S THE ENTIRE IDEA OF PRIVACY;    #
# nor do they have any idea of the capabilities of your system.                                                                             #
#																	    #
##########################################      I made this script to get my own answers.    ################################################

# How big do you want your truecrypt volume? Our statistics friends say that bigger is better.
size_GB=1

# Truecrypt only accepts size argument in bytes.
#        GB         MB     KB     byte
size=$(( $size_GB * 1024 * 1024 * 1024 ))






#############################################################################################################################################
# The variables above are the only ones that really need consideration when running the script. The variables below will help you customize #
# this script for your system, but do not need to be edited in most cases.                                                                  #
#############################################################################################################################################

# Specify a volume password to test with if you like.
# Default is a randomly generated 30 character alphanumeric password.
volpass=

# Improvements:
# 1. Make iteration a variable
# 2. Make algorithms an array so users can choose what to test
# 3. Make keyfile names from variables
# 3. Make keyfile quantity a variable

workingdir=$(pwd)
volume=$workingdir/truecryptvolume
#volume=/dev/shm/truecryptvolume
stats=$workingdir/stats.txt
mountpoint=$workingdir/truecrypt-benchmarking
# Benchmarking blocksize in kilobytes.
blocksize=$(( $size / 1024 ))

# Check write ability in our directories
if [[ ! -d $mountpoint  ]]
then
        if ! mkdir $mountpoint
	then
                echo "$mountpoint does not exist and I could not create the directory! Permissions maybe?"
                exit 1
        fi
fi

if [[ ! -e $volume ]]
then
	if ! touch $volume
	then
		echo "Cannot create volume, check permissions."
		exit 1
	fi
fi

echo BEGIN | tee $stats

for algorithm in AES Serpent Twofish AES-Twofish AES-Twofish-Serpent Serpent-AES Serpent-Twofish-AES Twofish-Serpent
do

	# Let's make it stupid clear what cipher is where in our output statistics file.
	echo -e ..................................................................................... | tee -a $stats
	echo -e $algorithm | tee -a $stats
	echo -e ..................................................................................... | tee -a $stats

	# Maybe I'll make iteration number a variable so it is expandable.
	for run in 1 2 3
	do

		echo --- RUN NUMBER $run of 3 using $algorithm --- | tee -a $stats
		# 30 character password seems about normal. This encodes urandom data into alphanumeric. (I know, boo-hoo, no symbols. Whatever.)
		if [[ -n $volpass ]]
		then
			encryptionpass=$volpass
		else
			encryptionpass=$( </dev/urandom tr -dc A-Za-z0-9 | head -c 30)
		fi
		# Truecrypt apparently only reads the first 1MB of the keyfile, so I'll make three.
		echo Generating keyfiles.
		# Need to make these variables in a for loop to determine number of keys
		# Like, "for 1 - $keyfilenumber do dd if=blah blah blah keyfile-$run.key"
		dd if=/dev/urandom of=./keyfile1.key bs=1M count=1 >/dev/null 2>&1
		dd if=/dev/urandom of=./keyfile2.key bs=1M count=1 >/dev/null 2>&1
		dd if=/dev/urandom of=./keyfile3.key bs=1M count=1 >/dev/null 2>&1
		echo Creating truecrypt volume. | tee -a $stats

			# truecrypt cannot create a filesystem in a block device, only on a disk partition.
			# we therefore have to create an empty volume and fill it ourselves with mkfs
			# time \
			truecrypt \
			--non-interactive \
			--hash=Whirlpool \
			--filesystem=none \
			--keyfiles=keyfile1.key,keyfile2.key,keyfile3.key \
			--random-source=/dev/urandom \
			--volume-type=normal \
			--size=$size\B  \
			--password='$encryptionpass' \
			--encryption=$algorithm \
			--create $volume >> $stats 2>&1

		# Truecrypt cannot mount our empty block device to a mountpoint, only to it's own
		# /dev/mapper/truecrypt; mountpoints will be ignored here.
		truecrypt \
		--non-interactive \
		--filesystem=none \
		--password='$encryptionpass' \
		--keyfiles=keyfile1.key,keyfile2.key,keyfile3.key \
		$volume

		# Where did you go Mr. Truecrypt?
		tcmount=$(truecrypt -l $volume | awk -F' ' '{print $3}')

		echo Filling truecrypt volume with Ext4 filesystem.
		mkfs.ext4 $tcmount >/dev/null

		truecrypt -d $volume

		echo Remounting filesystem to our own mountpoint.
                truecrypt \
                --non-interactive \
                --filesystem=ext4 \
                --password='$encryptionpass' \
                --keyfiles=keyfile1.key,keyfile2.key,keyfile3.key \
		--fs-options=noatime,data=writeback,barrier=0,nobh,errors=remount-ro \
                $volume $mountpoint

		# Time how long it takes to fill it with zeros or random data.
		echo Filling partition with zeros. \(Benchmark.\) | tee -a $stats
		# This will throw an error as it fills the truecrypt volume. That`s fine, it means it`s working.
		# We just wanna make sure the dd command isnt our bottleneck.
		# I'm using a block size of 64k because that is what the filesystem uses to read/write real files.
		# It is important to write only the correct amount even though it overflows. This keeps us
		# from accidentally filling the entire drive if something doesn't mount correctly.

		# Clear disk cache
		echo 3 > /proc/sys/vm/drop_caches

		echo Write test: | tee -a $stats
		dd if=/dev/zero of=$mountpoint/zeros bs=$blocksize count=$(( $size / $blocksize )) 2>&1 | grep --color=never copied >> $stats

		# Turns out that making a "zeros" file and copying it in and out of the mount really kills performance.
		# It's consistent, but very slow compared to copying from /dev/zero

		echo 3 > /proc/sys/vm/drop_caches

		echo Read test: | tee -a $stats
		dd if=$mountpoint/zeros of=/dev/null bs=$blocksize count=$(( $size / $blocksize )) 2>&1 | grep --color=never copied >> $stats

		echo 3 > /proc/sys/vm/drop_caches

		echo Unmounting.
		truecrypt -d $volume

		echo Cleaning up.
		rm $volume

		# Need to make these variables also
		rm keyfile1.key keyfile2.key keyfile3.key
	done

done

echo END


