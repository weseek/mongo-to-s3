#!/bin/bash -e

# settings
BACKUPFILE_PREFIX=${BACKUPFILE_PREFIX:-backup}
MONGODB_HOST=${MONGODB_HOST:-mongo}
CRONMODE=${CRONMODE:-false}
#MONGODB_URI=
#MONGODB_HOST=
#MONGODB_DBNAME=
#MONGODB_USERNAME=
#MONGODB_PASSWORD=
#MONGODB_AUTHDB=
#MONGODUMP_OPTS=
#TARGET_BUCKET_URL=[s3://... | gs://...] (must be ended with /)

# start script
CWD=`/usr/bin/dirname $0`
cd $CWD

. ./functions.sh
NOW=`create_current_yyyymmddhhmmss`

echo "=== $0 started at `/bin/date "+%Y/%m/%d %H:%M:%S"` ==="

TMPDIR="/tmp"
TARGET_DIRNAME="mongodump"
TARGET="${TMPDIR}/${TARGET_DIRNAME}"
TAR_CMD="/bin/tar"
TAR_OPTS="jcvf"

DIRNAME=`/usr/bin/dirname ${TARGET}`
BASENAME=`/usr/bin/basename ${TARGET}`
TARBALL="${BACKUPFILE_PREFIX}-${NOW}.tar.bz2"
TARBALL_FULLPATH="${TMPDIR}/${TARBALL}"


# check parameters
# deprecate the old option
if [ "x${S3_TARGET_BUCKET_URL}" != "x" ]; then
  echo "WARNING: The environment variable S3_TARGET_BUCKET_URL is deprecated.  Please use TARGET_BUCKET_URL instead."
  TARGET_BUCKET_URL=$S3_TARGET_BUCKET_URL
fi
if [ "x${TARGET_BUCKET_URL}" == "x" ]; then
  echo "ERROR: The environment variable TARGET_BUCKET_URL must be specified." 1>&2
  exit 1
fi

# dump database
if [ "x${MONGODB_URI}" != "x" ]; then
  MONGODUMP_OPTS="--uri=${MONGODB_URI} ${MONGODUMP_OPTS}"
else
  if [ "x${MONGODB_DBNAME}" != "x" ]; then
    MONGODUMP_OPTS="${MONGODUMP_OPTS} -d ${MONGODB_DBNAME}"
  fi
  if [ "x${MONGODB_USERNAME}" != "x" ]; then
    MONGODUMP_OPTS="${MONGODUMP_OPTS} -u ${MONGODB_USERNAME} -p ${MONGODB_PASSWORD}"
  fi
  if [ "x${MONGODB_AUTHDB}" != "x" ]; then
    MONGODUMP_OPTS="${MONGODUMP_OPTS} --authenticationDatabase ${MONGODB_AUTHDB}"
  fi
  MONGODUMP_OPTS="-h ${MONGODB_HOST} ${MONGODUMP_OPTS}"
fi
echo "dump MongoDB..."
mongodump -o ${TARGET} ${MONGODUMP_OPTS} --forceTableScan

# run tar command
echo "backup ${TARGET}..."
time ${TAR_CMD} ${TAR_OPTS} ${TARBALL_FULLPATH} -C ${DIRNAME} ${BASENAME}

if [ `echo $TARGET_BUCKET_URL | cut -f1 -d":"` == "s3" ]; then
  # transfer tarball to Amazon S3
  s3_copy_file ${TARBALL_FULLPATH} ${TARGET_BUCKET_URL}
elif [ `echo $TARGET_BUCKET_URL | cut -f1 -d":"` == "gs" ]; then
  gs_copy_file ${TARBALL_FULLPATH} ${TARGET_BUCKET_URL}
fi

# call healthchecks url for successful backup
if [ "x${HEALTHCHECKS_URL}" != "x" ]; then
  curl -fsS --retry 3 ${HEALTHCHECKS_URL} > /dev/null
fi

# clean up working files if in cron mode
if ${CRONMODE} ; then
  rm -rf ${TARGET}
  rm -f ${TARBALL_FULLPATH}
fi
