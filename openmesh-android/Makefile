.PHONY: go-lib go-lib-ps go-lib-sh

go-lib:
ifeq ($(OS),Windows_NT)
	powershell -ExecutionPolicy Bypass -File .\\scripts\\build-go-android-lib.ps1
else
	bash ./scripts/build-go-android-lib.sh
endif

go-lib-ps:
	powershell -ExecutionPolicy Bypass -File .\\scripts\\build-go-android-lib.ps1

go-lib-sh:
	bash ./scripts/build-go-android-lib.sh
