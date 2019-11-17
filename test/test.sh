#!/bin/sh

# test 1 function:
# bats freenom-funcs.bats -f func_getRec

  case $1 in 
    args)   bats freenom-args.bat ;;
    funcs)  bats freenom-funcs.bats ;;
    all)    if [ -d ./test ]; then
              ( bats -r ./test/freenom* -t )
            else
              echo "Run 'test/bats.sh all' from <repo> dir"
              exit 1
            fi
            ;;
    *)      echo "$(basename "$0") <args|funcs|all>"; exit 0 ;;
  esac
  exit 0
