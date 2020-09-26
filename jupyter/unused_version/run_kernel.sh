#!/bin/bash

# https://github.com/jupyter/enterprise_gateway/tree/v1.1.1/etc/kernelspecs/spark_python_yarn_client


echo -e "\nStarting python kernel for Spark\n"

echo "Loading ${PYTHON} module"
module load ${PYTHON}

if [ -z "${SPARK_HOME}" ]; then
  echo "SPARK_HOME must be set to the location of a Spark distribution!"
  exit 1
fi

export PYSPARK_DRIVER_PYTHON=$PYTHON
export PYSPARK_DRIVER_PYTHON_OPTS="$@"

set -x
eval exec "tacc-submit.sh" \
	"${LAUNCH_OPTS}" \
set +x
