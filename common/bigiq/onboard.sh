#!/bin/bash
source /config/onboard_functions.sh
function main() {
  echo -n "initialization started at: "; date
  SECONDS=0
  setup_init
  setup_host
  setup_cleanup
  duration=$SECONDS
  echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
  echo -n "initialization complete at: "; date
}
main
