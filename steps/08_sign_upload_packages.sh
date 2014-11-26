#!/bin/sh
export KEYID=B6CE4E93 # the key ID of the GPG key to sign deb packages

export DIR=${PWD#}
export OUTPUT_DIR=$DIR/output
export DOCKER_IMAGE=openrov/debian-repository
export PREFIX=""

if [ "$DEB_CODENAME" = "" ]; then
        echo "Please set the DEB_CODENAME environment variable to define into what debian repo we should upload the .deb files."
        exit 1
fi

if [ "$DEB_COMPONENT" = "" ]; then
        echo "Please set the DEB_COMPONENT environment variable to define into what debian component we should upload the .deb files."
        exit 1
fi

if [ "$AWS_CREDENTIALS" = "" ]; then
	if [ "$AWSKEY" = "" ] && [ "$AWSSECRET" = "" ]; then
        echo "Please set the AWS_CREDENTIALS environment variable containing the path to a file with the key/value pairs for AWSKEY and AWSSECRET"
        exit 1
    fi
fi

if [ "$GPG_PASSPHRASE_FILE" = "" ]; then
        echo "Please set the GPG_PASSPHRASE_FILE environment variable containing the filename to the passphrase used for the GPG key."
        exit 1
fi

if [ "$1" = "-t" ]; then
	PREFIX_VALUE=test
	if [ "$2" != "" ]; then
		PREFIX_VALUE=$2
	fi
	PREFIX=--prefix=$PREFIX_VALUE
fi

. $DIR/lib/libtools.sh
. $DIR/lib/libmount.sh
. $DIR/versions.sh
if [ !"$AWSKEY" = "" ] && [ !"$AWSSECRET" = "" ]; then
	. $AWS_CREDENTIALS # this is a environment variable that is set by the Jenkins Credentials Binding Plugin (see below) 
    	               # and it contains the path to a file with the AWS credentials as KEY=Value
fi
checkroot

cd $OUTPUT_DIR/packages

# Docker command descrioption:
# -t assigns a pseudo tty, we need that for gpg (used for signing packages and the deb repo)
# -v /host/path:/container/path  mapps the host path to the container path read/write
#    The packages folder contains the debian packages 
#    the $GPG_PASSPHRASE_FILE is a path to the passphrase. This file and the environment variable is created and maintained by 
#    the Credentials Binding Plugin for Jenkins (https://wiki.jenkins-ci.org/display/JENKINS/Credentials+Binding+Plugin)
# -e HOME=  sets the environment variable HOME

docker run \
	-t \
	-v $DIR/docker/deb-repository/gnupg/:/root/.gnupg \
	-v $OUTPUT_DIR/packages:/tmp/packages \
	-v ${GPG_PASSPHRASE_FILE}:/root/passphrase.txt \
	-e HOME=/root \
	${DOCKER_IMAGE} \
	dpkg-sig -k $KEYID \
		-g "--passphrase-file /root/passphrase.txt" \
		-s openrov \
		/tmp/packages/openrov*.deb 

docker run \
	-t \
	-v $DIR/docker/deb-repository/gnupg/:/root/.gnupg \
	-v $OUTPUT_DIR/packages:/tmp/packages \
	-v ${GPG_PASSPHRASE_FILE}:/root/passphrase.txt \
	-e HOME=/root \
	${DOCKER_IMAGE} \
	/tmp/deb-s3/bin/deb-s3 upload \
		--bucket=openrov-deb-repository \
		-p \
		-c $DEB_CODENAME \
        -m $DEB_COMPONENT \
        ${PREFIX} \
		--access-key-id=$AWSKEY \
		--secret-access-key=$AWSSECRET \
		--sign=$KEYID \
		--gpg-options="--passphrase-file /root/passphrase.txt" \
		/tmp/packages/openrov*.deb
