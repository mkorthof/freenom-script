#!/bin/sh

# test 1 function:
# bats freenom-funcs.bats -f func_getRec

func_msg () {
  test -n "$1" && echo "$(date '+%F %H:%M:%S') ${1}: test.sh"
}

case $1 in
  args)   trap 'func_msg "END"; exit' EXIT HUP INT TERM
          func_msg "START"
          bats freenom-args.bats
          ;;
  funcs)  trap 'func_msg "END"; exit' EXIT HUP INT TERM
          func_msg "START"
          bats freenom-funcs.bats
          ;;
  all)    func_msg "START"
          trap 'func_msg "END"; exit' EXIT HUP INT TERM
          if [ -d ./test ]; then
            ( bats -r ./test/freenom* -t )
          elif [ -f "freenom-args.bats" ] && [ -f "freenom-funcs.bats" ]; then
            ( cd .. && bats -r ./test/freenom* -t )
          else
            echo "ERROR: bats files not found"
            exit 1
          fi
          ;;
  *)      echo "$(basename "$0") <args|funcs|all>"
          exit 0
          ;;
esac
