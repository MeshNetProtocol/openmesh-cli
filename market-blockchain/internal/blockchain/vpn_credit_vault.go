// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package blockchain

import (
	"errors"
	"math/big"
	"strings"

	ethereum "github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/event"
)

// Reference imports to suppress errors if they are not otherwise used.
var (
	_ = errors.New
	_ = big.NewInt
	_ = strings.NewReader
	_ = ethereum.NotFound
	_ = bind.Bind
	_ = common.Big1
	_ = types.BloomLookup
	_ = event.NewSubscription
	_ = abi.ConvertType
)

// VPNCreditVaultMetaData contains all meta data concerning the VPNCreditVault contract.
var VPNCreditVaultMetaData = &bind.MetaData{
	ABI: "[{\"type\":\"constructor\",\"inputs\":[{\"name\":\"_usdc\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"_serviceWallet\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"_relayer\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"USDC_UNIT\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"authorizeChargeWithPermit\",\"inputs\":[{\"name\":\"user\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"identityAddress\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"expectedAllowance\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"targetAllowance\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"deadline\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"v\",\"type\":\"uint8\",\"internalType\":\"uint8\"},{\"name\":\"r\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"},{\"name\":\"s\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"authorizedAllowance\",\"inputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"cancelAuthorization\",\"inputs\":[{\"name\":\"user\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"identityAddress\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"expectedAllowance\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"targetAllowance\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"deadline\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"v\",\"type\":\"uint8\",\"internalType\":\"uint8\"},{\"name\":\"r\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"},{\"name\":\"s\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"charge\",\"inputs\":[{\"name\":\"chargeId\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"},{\"name\":\"identityAddress\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"amount\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"executedCharges\",\"inputs\":[{\"name\":\"\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"}],\"outputs\":[{\"name\":\"\",\"type\":\"bool\",\"internalType\":\"bool\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"getAuthorizedAllowance\",\"inputs\":[{\"name\":\"payer\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"identityAddress\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"getIdentityPayer\",\"inputs\":[{\"name\":\"identityAddress\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"payer\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"identityToPayer\",\"inputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"owner\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"relayer\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"renounceOwnership\",\"inputs\":[],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"serviceWallet\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"setRelayer\",\"inputs\":[{\"name\":\"_relayer\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"setServiceWallet\",\"inputs\":[{\"name\":\"_serviceWallet\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"transferOwnership\",\"inputs\":[{\"name\":\"newOwner\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"usdc\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"contractIERC20Permit\"}],\"stateMutability\":\"view\"},{\"type\":\"event\",\"name\":\"ChargeAuthorized\",\"inputs\":[{\"name\":\"payer\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"identity\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"expectedAllowance\",\"type\":\"uint256\",\"indexed\":false,\"internalType\":\"uint256\"},{\"name\":\"targetAllowance\",\"type\":\"uint256\",\"indexed\":false,\"internalType\":\"uint256\"}],\"anonymous\":false},{\"type\":\"event\",\"name\":\"IdentityBound\",\"inputs\":[{\"name\":\"payer\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"identity\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"}],\"anonymous\":false},{\"type\":\"event\",\"name\":\"IdentityCharged\",\"inputs\":[{\"name\":\"chargeId\",\"type\":\"bytes32\",\"indexed\":true,\"internalType\":\"bytes32\"},{\"name\":\"payer\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"identity\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"amount\",\"type\":\"uint256\",\"indexed\":false,\"internalType\":\"uint256\"}],\"anonymous\":false},{\"type\":\"event\",\"name\":\"OwnershipTransferred\",\"inputs\":[{\"name\":\"previousOwner\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"newOwner\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"}],\"anonymous\":false},{\"type\":\"error\",\"name\":\"OwnableInvalidOwner\",\"inputs\":[{\"name\":\"owner\",\"type\":\"address\",\"internalType\":\"address\"}]},{\"type\":\"error\",\"name\":\"OwnableUnauthorizedAccount\",\"inputs\":[{\"name\":\"account\",\"type\":\"address\",\"internalType\":\"address\"}]}]",
}

// VPNCreditVaultABI is the input ABI used to generate the binding from.
// Deprecated: Use VPNCreditVaultMetaData.ABI instead.
var VPNCreditVaultABI = VPNCreditVaultMetaData.ABI

// VPNCreditVault is an auto generated Go binding around an Ethereum contract.
type VPNCreditVault struct {
	VPNCreditVaultCaller     // Read-only binding to the contract
	VPNCreditVaultTransactor // Write-only binding to the contract
	VPNCreditVaultFilterer   // Log filterer for contract events
}

// VPNCreditVaultCaller is an auto generated read-only Go binding around an Ethereum contract.
type VPNCreditVaultCaller struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// VPNCreditVaultTransactor is an auto generated write-only Go binding around an Ethereum contract.
type VPNCreditVaultTransactor struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// VPNCreditVaultFilterer is an auto generated log filtering Go binding around an Ethereum contract events.
type VPNCreditVaultFilterer struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// VPNCreditVaultSession is an auto generated Go binding around an Ethereum contract,
// with pre-set call and transact options.
type VPNCreditVaultSession struct {
	Contract     *VPNCreditVault   // Generic contract binding to set the session for
	CallOpts     bind.CallOpts     // Call options to use throughout this session
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// VPNCreditVaultCallerSession is an auto generated read-only Go binding around an Ethereum contract,
// with pre-set call options.
type VPNCreditVaultCallerSession struct {
	Contract *VPNCreditVaultCaller // Generic contract caller binding to set the session for
	CallOpts bind.CallOpts         // Call options to use throughout this session
}

// VPNCreditVaultTransactorSession is an auto generated write-only Go binding around an Ethereum contract,
// with pre-set transact options.
type VPNCreditVaultTransactorSession struct {
	Contract     *VPNCreditVaultTransactor // Generic contract transactor binding to set the session for
	TransactOpts bind.TransactOpts         // Transaction auth options to use throughout this session
}

// VPNCreditVaultRaw is an auto generated low-level Go binding around an Ethereum contract.
type VPNCreditVaultRaw struct {
	Contract *VPNCreditVault // Generic contract binding to access the raw methods on
}

// VPNCreditVaultCallerRaw is an auto generated low-level read-only Go binding around an Ethereum contract.
type VPNCreditVaultCallerRaw struct {
	Contract *VPNCreditVaultCaller // Generic read-only contract binding to access the raw methods on
}

// VPNCreditVaultTransactorRaw is an auto generated low-level write-only Go binding around an Ethereum contract.
type VPNCreditVaultTransactorRaw struct {
	Contract *VPNCreditVaultTransactor // Generic write-only contract binding to access the raw methods on
}

// NewVPNCreditVault creates a new instance of VPNCreditVault, bound to a specific deployed contract.
func NewVPNCreditVault(address common.Address, backend bind.ContractBackend) (*VPNCreditVault, error) {
	contract, err := bindVPNCreditVault(address, backend, backend, backend)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVault{VPNCreditVaultCaller: VPNCreditVaultCaller{contract: contract}, VPNCreditVaultTransactor: VPNCreditVaultTransactor{contract: contract}, VPNCreditVaultFilterer: VPNCreditVaultFilterer{contract: contract}}, nil
}

// NewVPNCreditVaultCaller creates a new read-only instance of VPNCreditVault, bound to a specific deployed contract.
func NewVPNCreditVaultCaller(address common.Address, caller bind.ContractCaller) (*VPNCreditVaultCaller, error) {
	contract, err := bindVPNCreditVault(address, caller, nil, nil)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVaultCaller{contract: contract}, nil
}

// NewVPNCreditVaultTransactor creates a new write-only instance of VPNCreditVault, bound to a specific deployed contract.
func NewVPNCreditVaultTransactor(address common.Address, transactor bind.ContractTransactor) (*VPNCreditVaultTransactor, error) {
	contract, err := bindVPNCreditVault(address, nil, transactor, nil)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVaultTransactor{contract: contract}, nil
}

// NewVPNCreditVaultFilterer creates a new log filterer instance of VPNCreditVault, bound to a specific deployed contract.
func NewVPNCreditVaultFilterer(address common.Address, filterer bind.ContractFilterer) (*VPNCreditVaultFilterer, error) {
	contract, err := bindVPNCreditVault(address, nil, nil, filterer)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVaultFilterer{contract: contract}, nil
}

// bindVPNCreditVault binds a generic wrapper to an already deployed contract.
func bindVPNCreditVault(address common.Address, caller bind.ContractCaller, transactor bind.ContractTransactor, filterer bind.ContractFilterer) (*bind.BoundContract, error) {
	parsed, err := VPNCreditVaultMetaData.GetAbi()
	if err != nil {
		return nil, err
	}
	return bind.NewBoundContract(address, *parsed, caller, transactor, filterer), nil
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_VPNCreditVault *VPNCreditVaultRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _VPNCreditVault.Contract.VPNCreditVaultCaller.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_VPNCreditVault *VPNCreditVaultRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.VPNCreditVaultTransactor.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_VPNCreditVault *VPNCreditVaultRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.VPNCreditVaultTransactor.contract.Transact(opts, method, params...)
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_VPNCreditVault *VPNCreditVaultCallerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _VPNCreditVault.Contract.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_VPNCreditVault *VPNCreditVaultTransactorRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_VPNCreditVault *VPNCreditVaultTransactorRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.contract.Transact(opts, method, params...)
}

// USDCUNIT is a free data retrieval call binding the contract method 0x4af28676.
//
// Solidity: function USDC_UNIT() view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultCaller) USDCUNIT(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "USDC_UNIT")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// USDCUNIT is a free data retrieval call binding the contract method 0x4af28676.
//
// Solidity: function USDC_UNIT() view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultSession) USDCUNIT() (*big.Int, error) {
	return _VPNCreditVault.Contract.USDCUNIT(&_VPNCreditVault.CallOpts)
}

// USDCUNIT is a free data retrieval call binding the contract method 0x4af28676.
//
// Solidity: function USDC_UNIT() view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultCallerSession) USDCUNIT() (*big.Int, error) {
	return _VPNCreditVault.Contract.USDCUNIT(&_VPNCreditVault.CallOpts)
}

// AuthorizedAllowance is a free data retrieval call binding the contract method 0x58b3d5ae.
//
// Solidity: function authorizedAllowance(address , address ) view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultCaller) AuthorizedAllowance(opts *bind.CallOpts, arg0 common.Address, arg1 common.Address) (*big.Int, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "authorizedAllowance", arg0, arg1)

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// AuthorizedAllowance is a free data retrieval call binding the contract method 0x58b3d5ae.
//
// Solidity: function authorizedAllowance(address , address ) view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultSession) AuthorizedAllowance(arg0 common.Address, arg1 common.Address) (*big.Int, error) {
	return _VPNCreditVault.Contract.AuthorizedAllowance(&_VPNCreditVault.CallOpts, arg0, arg1)
}

// AuthorizedAllowance is a free data retrieval call binding the contract method 0x58b3d5ae.
//
// Solidity: function authorizedAllowance(address , address ) view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultCallerSession) AuthorizedAllowance(arg0 common.Address, arg1 common.Address) (*big.Int, error) {
	return _VPNCreditVault.Contract.AuthorizedAllowance(&_VPNCreditVault.CallOpts, arg0, arg1)
}

// ExecutedCharges is a free data retrieval call binding the contract method 0x201ec80d.
//
// Solidity: function executedCharges(bytes32 ) view returns(bool)
func (_VPNCreditVault *VPNCreditVaultCaller) ExecutedCharges(opts *bind.CallOpts, arg0 [32]byte) (bool, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "executedCharges", arg0)

	if err != nil {
		return *new(bool), err
	}

	out0 := *abi.ConvertType(out[0], new(bool)).(*bool)

	return out0, err

}

// ExecutedCharges is a free data retrieval call binding the contract method 0x201ec80d.
//
// Solidity: function executedCharges(bytes32 ) view returns(bool)
func (_VPNCreditVault *VPNCreditVaultSession) ExecutedCharges(arg0 [32]byte) (bool, error) {
	return _VPNCreditVault.Contract.ExecutedCharges(&_VPNCreditVault.CallOpts, arg0)
}

// ExecutedCharges is a free data retrieval call binding the contract method 0x201ec80d.
//
// Solidity: function executedCharges(bytes32 ) view returns(bool)
func (_VPNCreditVault *VPNCreditVaultCallerSession) ExecutedCharges(arg0 [32]byte) (bool, error) {
	return _VPNCreditVault.Contract.ExecutedCharges(&_VPNCreditVault.CallOpts, arg0)
}

// GetAuthorizedAllowance is a free data retrieval call binding the contract method 0xb484c539.
//
// Solidity: function getAuthorizedAllowance(address payer, address identityAddress) view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultCaller) GetAuthorizedAllowance(opts *bind.CallOpts, payer common.Address, identityAddress common.Address) (*big.Int, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "getAuthorizedAllowance", payer, identityAddress)

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// GetAuthorizedAllowance is a free data retrieval call binding the contract method 0xb484c539.
//
// Solidity: function getAuthorizedAllowance(address payer, address identityAddress) view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultSession) GetAuthorizedAllowance(payer common.Address, identityAddress common.Address) (*big.Int, error) {
	return _VPNCreditVault.Contract.GetAuthorizedAllowance(&_VPNCreditVault.CallOpts, payer, identityAddress)
}

// GetAuthorizedAllowance is a free data retrieval call binding the contract method 0xb484c539.
//
// Solidity: function getAuthorizedAllowance(address payer, address identityAddress) view returns(uint256)
func (_VPNCreditVault *VPNCreditVaultCallerSession) GetAuthorizedAllowance(payer common.Address, identityAddress common.Address) (*big.Int, error) {
	return _VPNCreditVault.Contract.GetAuthorizedAllowance(&_VPNCreditVault.CallOpts, payer, identityAddress)
}

// GetIdentityPayer is a free data retrieval call binding the contract method 0x4e841ffa.
//
// Solidity: function getIdentityPayer(address identityAddress) view returns(address payer)
func (_VPNCreditVault *VPNCreditVaultCaller) GetIdentityPayer(opts *bind.CallOpts, identityAddress common.Address) (common.Address, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "getIdentityPayer", identityAddress)

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// GetIdentityPayer is a free data retrieval call binding the contract method 0x4e841ffa.
//
// Solidity: function getIdentityPayer(address identityAddress) view returns(address payer)
func (_VPNCreditVault *VPNCreditVaultSession) GetIdentityPayer(identityAddress common.Address) (common.Address, error) {
	return _VPNCreditVault.Contract.GetIdentityPayer(&_VPNCreditVault.CallOpts, identityAddress)
}

// GetIdentityPayer is a free data retrieval call binding the contract method 0x4e841ffa.
//
// Solidity: function getIdentityPayer(address identityAddress) view returns(address payer)
func (_VPNCreditVault *VPNCreditVaultCallerSession) GetIdentityPayer(identityAddress common.Address) (common.Address, error) {
	return _VPNCreditVault.Contract.GetIdentityPayer(&_VPNCreditVault.CallOpts, identityAddress)
}

// IdentityToPayer is a free data retrieval call binding the contract method 0x414b4575.
//
// Solidity: function identityToPayer(address ) view returns(address)
func (_VPNCreditVault *VPNCreditVaultCaller) IdentityToPayer(opts *bind.CallOpts, arg0 common.Address) (common.Address, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "identityToPayer", arg0)

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// IdentityToPayer is a free data retrieval call binding the contract method 0x414b4575.
//
// Solidity: function identityToPayer(address ) view returns(address)
func (_VPNCreditVault *VPNCreditVaultSession) IdentityToPayer(arg0 common.Address) (common.Address, error) {
	return _VPNCreditVault.Contract.IdentityToPayer(&_VPNCreditVault.CallOpts, arg0)
}

// IdentityToPayer is a free data retrieval call binding the contract method 0x414b4575.
//
// Solidity: function identityToPayer(address ) view returns(address)
func (_VPNCreditVault *VPNCreditVaultCallerSession) IdentityToPayer(arg0 common.Address) (common.Address, error) {
	return _VPNCreditVault.Contract.IdentityToPayer(&_VPNCreditVault.CallOpts, arg0)
}

// Owner is a free data retrieval call binding the contract method 0x8da5cb5b.
//
// Solidity: function owner() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCaller) Owner(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "owner")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// Owner is a free data retrieval call binding the contract method 0x8da5cb5b.
//
// Solidity: function owner() view returns(address)
func (_VPNCreditVault *VPNCreditVaultSession) Owner() (common.Address, error) {
	return _VPNCreditVault.Contract.Owner(&_VPNCreditVault.CallOpts)
}

// Owner is a free data retrieval call binding the contract method 0x8da5cb5b.
//
// Solidity: function owner() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCallerSession) Owner() (common.Address, error) {
	return _VPNCreditVault.Contract.Owner(&_VPNCreditVault.CallOpts)
}

// Relayer is a free data retrieval call binding the contract method 0x8406c079.
//
// Solidity: function relayer() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCaller) Relayer(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "relayer")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// Relayer is a free data retrieval call binding the contract method 0x8406c079.
//
// Solidity: function relayer() view returns(address)
func (_VPNCreditVault *VPNCreditVaultSession) Relayer() (common.Address, error) {
	return _VPNCreditVault.Contract.Relayer(&_VPNCreditVault.CallOpts)
}

// Relayer is a free data retrieval call binding the contract method 0x8406c079.
//
// Solidity: function relayer() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCallerSession) Relayer() (common.Address, error) {
	return _VPNCreditVault.Contract.Relayer(&_VPNCreditVault.CallOpts)
}

// ServiceWallet is a free data retrieval call binding the contract method 0x5641f3c3.
//
// Solidity: function serviceWallet() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCaller) ServiceWallet(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "serviceWallet")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// ServiceWallet is a free data retrieval call binding the contract method 0x5641f3c3.
//
// Solidity: function serviceWallet() view returns(address)
func (_VPNCreditVault *VPNCreditVaultSession) ServiceWallet() (common.Address, error) {
	return _VPNCreditVault.Contract.ServiceWallet(&_VPNCreditVault.CallOpts)
}

// ServiceWallet is a free data retrieval call binding the contract method 0x5641f3c3.
//
// Solidity: function serviceWallet() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCallerSession) ServiceWallet() (common.Address, error) {
	return _VPNCreditVault.Contract.ServiceWallet(&_VPNCreditVault.CallOpts)
}

// Usdc is a free data retrieval call binding the contract method 0x3e413bee.
//
// Solidity: function usdc() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCaller) Usdc(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _VPNCreditVault.contract.Call(opts, &out, "usdc")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// Usdc is a free data retrieval call binding the contract method 0x3e413bee.
//
// Solidity: function usdc() view returns(address)
func (_VPNCreditVault *VPNCreditVaultSession) Usdc() (common.Address, error) {
	return _VPNCreditVault.Contract.Usdc(&_VPNCreditVault.CallOpts)
}

// Usdc is a free data retrieval call binding the contract method 0x3e413bee.
//
// Solidity: function usdc() view returns(address)
func (_VPNCreditVault *VPNCreditVaultCallerSession) Usdc() (common.Address, error) {
	return _VPNCreditVault.Contract.Usdc(&_VPNCreditVault.CallOpts)
}

// AuthorizeChargeWithPermit is a paid mutator transaction binding the contract method 0x2fb7326f.
//
// Solidity: function authorizeChargeWithPermit(address user, address identityAddress, uint256 expectedAllowance, uint256 targetAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s) returns()
func (_VPNCreditVault *VPNCreditVaultTransactor) AuthorizeChargeWithPermit(opts *bind.TransactOpts, user common.Address, identityAddress common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, v uint8, r [32]byte, s [32]byte) (*types.Transaction, error) {
	return _VPNCreditVault.contract.Transact(opts, "authorizeChargeWithPermit", user, identityAddress, expectedAllowance, targetAllowance, deadline, v, r, s)
}

// AuthorizeChargeWithPermit is a paid mutator transaction binding the contract method 0x2fb7326f.
//
// Solidity: function authorizeChargeWithPermit(address user, address identityAddress, uint256 expectedAllowance, uint256 targetAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s) returns()
func (_VPNCreditVault *VPNCreditVaultSession) AuthorizeChargeWithPermit(user common.Address, identityAddress common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, v uint8, r [32]byte, s [32]byte) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.AuthorizeChargeWithPermit(&_VPNCreditVault.TransactOpts, user, identityAddress, expectedAllowance, targetAllowance, deadline, v, r, s)
}

// AuthorizeChargeWithPermit is a paid mutator transaction binding the contract method 0x2fb7326f.
//
// Solidity: function authorizeChargeWithPermit(address user, address identityAddress, uint256 expectedAllowance, uint256 targetAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s) returns()
func (_VPNCreditVault *VPNCreditVaultTransactorSession) AuthorizeChargeWithPermit(user common.Address, identityAddress common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, v uint8, r [32]byte, s [32]byte) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.AuthorizeChargeWithPermit(&_VPNCreditVault.TransactOpts, user, identityAddress, expectedAllowance, targetAllowance, deadline, v, r, s)
}

// CancelAuthorization is a paid mutator transaction binding the contract method 0x1d8ea5c2.
//
// Solidity: function cancelAuthorization(address user, address identityAddress, uint256 expectedAllowance, uint256 targetAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s) returns()
func (_VPNCreditVault *VPNCreditVaultTransactor) CancelAuthorization(opts *bind.TransactOpts, user common.Address, identityAddress common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, v uint8, r [32]byte, s [32]byte) (*types.Transaction, error) {
	return _VPNCreditVault.contract.Transact(opts, "cancelAuthorization", user, identityAddress, expectedAllowance, targetAllowance, deadline, v, r, s)
}

// CancelAuthorization is a paid mutator transaction binding the contract method 0x1d8ea5c2.
//
// Solidity: function cancelAuthorization(address user, address identityAddress, uint256 expectedAllowance, uint256 targetAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s) returns()
func (_VPNCreditVault *VPNCreditVaultSession) CancelAuthorization(user common.Address, identityAddress common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, v uint8, r [32]byte, s [32]byte) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.CancelAuthorization(&_VPNCreditVault.TransactOpts, user, identityAddress, expectedAllowance, targetAllowance, deadline, v, r, s)
}

// CancelAuthorization is a paid mutator transaction binding the contract method 0x1d8ea5c2.
//
// Solidity: function cancelAuthorization(address user, address identityAddress, uint256 expectedAllowance, uint256 targetAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s) returns()
func (_VPNCreditVault *VPNCreditVaultTransactorSession) CancelAuthorization(user common.Address, identityAddress common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, v uint8, r [32]byte, s [32]byte) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.CancelAuthorization(&_VPNCreditVault.TransactOpts, user, identityAddress, expectedAllowance, targetAllowance, deadline, v, r, s)
}

// Charge is a paid mutator transaction binding the contract method 0x08a4ec2f.
//
// Solidity: function charge(bytes32 chargeId, address identityAddress, uint256 amount) returns()
func (_VPNCreditVault *VPNCreditVaultTransactor) Charge(opts *bind.TransactOpts, chargeId [32]byte, identityAddress common.Address, amount *big.Int) (*types.Transaction, error) {
	return _VPNCreditVault.contract.Transact(opts, "charge", chargeId, identityAddress, amount)
}

// Charge is a paid mutator transaction binding the contract method 0x08a4ec2f.
//
// Solidity: function charge(bytes32 chargeId, address identityAddress, uint256 amount) returns()
func (_VPNCreditVault *VPNCreditVaultSession) Charge(chargeId [32]byte, identityAddress common.Address, amount *big.Int) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.Charge(&_VPNCreditVault.TransactOpts, chargeId, identityAddress, amount)
}

// Charge is a paid mutator transaction binding the contract method 0x08a4ec2f.
//
// Solidity: function charge(bytes32 chargeId, address identityAddress, uint256 amount) returns()
func (_VPNCreditVault *VPNCreditVaultTransactorSession) Charge(chargeId [32]byte, identityAddress common.Address, amount *big.Int) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.Charge(&_VPNCreditVault.TransactOpts, chargeId, identityAddress, amount)
}

// RenounceOwnership is a paid mutator transaction binding the contract method 0x715018a6.
//
// Solidity: function renounceOwnership() returns()
func (_VPNCreditVault *VPNCreditVaultTransactor) RenounceOwnership(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _VPNCreditVault.contract.Transact(opts, "renounceOwnership")
}

// RenounceOwnership is a paid mutator transaction binding the contract method 0x715018a6.
//
// Solidity: function renounceOwnership() returns()
func (_VPNCreditVault *VPNCreditVaultSession) RenounceOwnership() (*types.Transaction, error) {
	return _VPNCreditVault.Contract.RenounceOwnership(&_VPNCreditVault.TransactOpts)
}

// RenounceOwnership is a paid mutator transaction binding the contract method 0x715018a6.
//
// Solidity: function renounceOwnership() returns()
func (_VPNCreditVault *VPNCreditVaultTransactorSession) RenounceOwnership() (*types.Transaction, error) {
	return _VPNCreditVault.Contract.RenounceOwnership(&_VPNCreditVault.TransactOpts)
}

// SetRelayer is a paid mutator transaction binding the contract method 0x6548e9bc.
//
// Solidity: function setRelayer(address _relayer) returns()
func (_VPNCreditVault *VPNCreditVaultTransactor) SetRelayer(opts *bind.TransactOpts, _relayer common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.contract.Transact(opts, "setRelayer", _relayer)
}

// SetRelayer is a paid mutator transaction binding the contract method 0x6548e9bc.
//
// Solidity: function setRelayer(address _relayer) returns()
func (_VPNCreditVault *VPNCreditVaultSession) SetRelayer(_relayer common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.SetRelayer(&_VPNCreditVault.TransactOpts, _relayer)
}

// SetRelayer is a paid mutator transaction binding the contract method 0x6548e9bc.
//
// Solidity: function setRelayer(address _relayer) returns()
func (_VPNCreditVault *VPNCreditVaultTransactorSession) SetRelayer(_relayer common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.SetRelayer(&_VPNCreditVault.TransactOpts, _relayer)
}

// SetServiceWallet is a paid mutator transaction binding the contract method 0x23bffccc.
//
// Solidity: function setServiceWallet(address _serviceWallet) returns()
func (_VPNCreditVault *VPNCreditVaultTransactor) SetServiceWallet(opts *bind.TransactOpts, _serviceWallet common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.contract.Transact(opts, "setServiceWallet", _serviceWallet)
}

// SetServiceWallet is a paid mutator transaction binding the contract method 0x23bffccc.
//
// Solidity: function setServiceWallet(address _serviceWallet) returns()
func (_VPNCreditVault *VPNCreditVaultSession) SetServiceWallet(_serviceWallet common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.SetServiceWallet(&_VPNCreditVault.TransactOpts, _serviceWallet)
}

// SetServiceWallet is a paid mutator transaction binding the contract method 0x23bffccc.
//
// Solidity: function setServiceWallet(address _serviceWallet) returns()
func (_VPNCreditVault *VPNCreditVaultTransactorSession) SetServiceWallet(_serviceWallet common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.SetServiceWallet(&_VPNCreditVault.TransactOpts, _serviceWallet)
}

// TransferOwnership is a paid mutator transaction binding the contract method 0xf2fde38b.
//
// Solidity: function transferOwnership(address newOwner) returns()
func (_VPNCreditVault *VPNCreditVaultTransactor) TransferOwnership(opts *bind.TransactOpts, newOwner common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.contract.Transact(opts, "transferOwnership", newOwner)
}

// TransferOwnership is a paid mutator transaction binding the contract method 0xf2fde38b.
//
// Solidity: function transferOwnership(address newOwner) returns()
func (_VPNCreditVault *VPNCreditVaultSession) TransferOwnership(newOwner common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.TransferOwnership(&_VPNCreditVault.TransactOpts, newOwner)
}

// TransferOwnership is a paid mutator transaction binding the contract method 0xf2fde38b.
//
// Solidity: function transferOwnership(address newOwner) returns()
func (_VPNCreditVault *VPNCreditVaultTransactorSession) TransferOwnership(newOwner common.Address) (*types.Transaction, error) {
	return _VPNCreditVault.Contract.TransferOwnership(&_VPNCreditVault.TransactOpts, newOwner)
}

// VPNCreditVaultChargeAuthorizedIterator is returned from FilterChargeAuthorized and is used to iterate over the raw logs and unpacked data for ChargeAuthorized events raised by the VPNCreditVault contract.
type VPNCreditVaultChargeAuthorizedIterator struct {
	Event *VPNCreditVaultChargeAuthorized // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *VPNCreditVaultChargeAuthorizedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(VPNCreditVaultChargeAuthorized)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(VPNCreditVaultChargeAuthorized)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *VPNCreditVaultChargeAuthorizedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *VPNCreditVaultChargeAuthorizedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// VPNCreditVaultChargeAuthorized represents a ChargeAuthorized event raised by the VPNCreditVault contract.
type VPNCreditVaultChargeAuthorized struct {
	Payer             common.Address
	Identity          common.Address
	ExpectedAllowance *big.Int
	TargetAllowance   *big.Int
	Raw               types.Log // Blockchain specific contextual infos
}

// FilterChargeAuthorized is a free log retrieval operation binding the contract event 0x4ee1350ae4d477d74ec736b7953101e7558242f36aafedb2eced642715f114b7.
//
// Solidity: event ChargeAuthorized(address indexed payer, address indexed identity, uint256 expectedAllowance, uint256 targetAllowance)
func (_VPNCreditVault *VPNCreditVaultFilterer) FilterChargeAuthorized(opts *bind.FilterOpts, payer []common.Address, identity []common.Address) (*VPNCreditVaultChargeAuthorizedIterator, error) {

	var payerRule []interface{}
	for _, payerItem := range payer {
		payerRule = append(payerRule, payerItem)
	}
	var identityRule []interface{}
	for _, identityItem := range identity {
		identityRule = append(identityRule, identityItem)
	}

	logs, sub, err := _VPNCreditVault.contract.FilterLogs(opts, "ChargeAuthorized", payerRule, identityRule)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVaultChargeAuthorizedIterator{contract: _VPNCreditVault.contract, event: "ChargeAuthorized", logs: logs, sub: sub}, nil
}

// WatchChargeAuthorized is a free log subscription operation binding the contract event 0x4ee1350ae4d477d74ec736b7953101e7558242f36aafedb2eced642715f114b7.
//
// Solidity: event ChargeAuthorized(address indexed payer, address indexed identity, uint256 expectedAllowance, uint256 targetAllowance)
func (_VPNCreditVault *VPNCreditVaultFilterer) WatchChargeAuthorized(opts *bind.WatchOpts, sink chan<- *VPNCreditVaultChargeAuthorized, payer []common.Address, identity []common.Address) (event.Subscription, error) {

	var payerRule []interface{}
	for _, payerItem := range payer {
		payerRule = append(payerRule, payerItem)
	}
	var identityRule []interface{}
	for _, identityItem := range identity {
		identityRule = append(identityRule, identityItem)
	}

	logs, sub, err := _VPNCreditVault.contract.WatchLogs(opts, "ChargeAuthorized", payerRule, identityRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(VPNCreditVaultChargeAuthorized)
				if err := _VPNCreditVault.contract.UnpackLog(event, "ChargeAuthorized", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseChargeAuthorized is a log parse operation binding the contract event 0x4ee1350ae4d477d74ec736b7953101e7558242f36aafedb2eced642715f114b7.
//
// Solidity: event ChargeAuthorized(address indexed payer, address indexed identity, uint256 expectedAllowance, uint256 targetAllowance)
func (_VPNCreditVault *VPNCreditVaultFilterer) ParseChargeAuthorized(log types.Log) (*VPNCreditVaultChargeAuthorized, error) {
	event := new(VPNCreditVaultChargeAuthorized)
	if err := _VPNCreditVault.contract.UnpackLog(event, "ChargeAuthorized", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// VPNCreditVaultIdentityBoundIterator is returned from FilterIdentityBound and is used to iterate over the raw logs and unpacked data for IdentityBound events raised by the VPNCreditVault contract.
type VPNCreditVaultIdentityBoundIterator struct {
	Event *VPNCreditVaultIdentityBound // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *VPNCreditVaultIdentityBoundIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(VPNCreditVaultIdentityBound)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(VPNCreditVaultIdentityBound)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *VPNCreditVaultIdentityBoundIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *VPNCreditVaultIdentityBoundIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// VPNCreditVaultIdentityBound represents a IdentityBound event raised by the VPNCreditVault contract.
type VPNCreditVaultIdentityBound struct {
	Payer    common.Address
	Identity common.Address
	Raw      types.Log // Blockchain specific contextual infos
}

// FilterIdentityBound is a free log retrieval operation binding the contract event 0x5923c539ad9399ab68de39aaf87b99779f53a9a707940f98f8b30d1aadd73d51.
//
// Solidity: event IdentityBound(address indexed payer, address indexed identity)
func (_VPNCreditVault *VPNCreditVaultFilterer) FilterIdentityBound(opts *bind.FilterOpts, payer []common.Address, identity []common.Address) (*VPNCreditVaultIdentityBoundIterator, error) {

	var payerRule []interface{}
	for _, payerItem := range payer {
		payerRule = append(payerRule, payerItem)
	}
	var identityRule []interface{}
	for _, identityItem := range identity {
		identityRule = append(identityRule, identityItem)
	}

	logs, sub, err := _VPNCreditVault.contract.FilterLogs(opts, "IdentityBound", payerRule, identityRule)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVaultIdentityBoundIterator{contract: _VPNCreditVault.contract, event: "IdentityBound", logs: logs, sub: sub}, nil
}

// WatchIdentityBound is a free log subscription operation binding the contract event 0x5923c539ad9399ab68de39aaf87b99779f53a9a707940f98f8b30d1aadd73d51.
//
// Solidity: event IdentityBound(address indexed payer, address indexed identity)
func (_VPNCreditVault *VPNCreditVaultFilterer) WatchIdentityBound(opts *bind.WatchOpts, sink chan<- *VPNCreditVaultIdentityBound, payer []common.Address, identity []common.Address) (event.Subscription, error) {

	var payerRule []interface{}
	for _, payerItem := range payer {
		payerRule = append(payerRule, payerItem)
	}
	var identityRule []interface{}
	for _, identityItem := range identity {
		identityRule = append(identityRule, identityItem)
	}

	logs, sub, err := _VPNCreditVault.contract.WatchLogs(opts, "IdentityBound", payerRule, identityRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(VPNCreditVaultIdentityBound)
				if err := _VPNCreditVault.contract.UnpackLog(event, "IdentityBound", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseIdentityBound is a log parse operation binding the contract event 0x5923c539ad9399ab68de39aaf87b99779f53a9a707940f98f8b30d1aadd73d51.
//
// Solidity: event IdentityBound(address indexed payer, address indexed identity)
func (_VPNCreditVault *VPNCreditVaultFilterer) ParseIdentityBound(log types.Log) (*VPNCreditVaultIdentityBound, error) {
	event := new(VPNCreditVaultIdentityBound)
	if err := _VPNCreditVault.contract.UnpackLog(event, "IdentityBound", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// VPNCreditVaultIdentityChargedIterator is returned from FilterIdentityCharged and is used to iterate over the raw logs and unpacked data for IdentityCharged events raised by the VPNCreditVault contract.
type VPNCreditVaultIdentityChargedIterator struct {
	Event *VPNCreditVaultIdentityCharged // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *VPNCreditVaultIdentityChargedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(VPNCreditVaultIdentityCharged)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(VPNCreditVaultIdentityCharged)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *VPNCreditVaultIdentityChargedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *VPNCreditVaultIdentityChargedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// VPNCreditVaultIdentityCharged represents a IdentityCharged event raised by the VPNCreditVault contract.
type VPNCreditVaultIdentityCharged struct {
	ChargeId [32]byte
	Payer    common.Address
	Identity common.Address
	Amount   *big.Int
	Raw      types.Log // Blockchain specific contextual infos
}

// FilterIdentityCharged is a free log retrieval operation binding the contract event 0xb9cf8c9dbbc25fc6c2c7a0a87ca2ccb300ef8c27ca5b1879072585f93143159f.
//
// Solidity: event IdentityCharged(bytes32 indexed chargeId, address indexed payer, address indexed identity, uint256 amount)
func (_VPNCreditVault *VPNCreditVaultFilterer) FilterIdentityCharged(opts *bind.FilterOpts, chargeId [][32]byte, payer []common.Address, identity []common.Address) (*VPNCreditVaultIdentityChargedIterator, error) {

	var chargeIdRule []interface{}
	for _, chargeIdItem := range chargeId {
		chargeIdRule = append(chargeIdRule, chargeIdItem)
	}
	var payerRule []interface{}
	for _, payerItem := range payer {
		payerRule = append(payerRule, payerItem)
	}
	var identityRule []interface{}
	for _, identityItem := range identity {
		identityRule = append(identityRule, identityItem)
	}

	logs, sub, err := _VPNCreditVault.contract.FilterLogs(opts, "IdentityCharged", chargeIdRule, payerRule, identityRule)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVaultIdentityChargedIterator{contract: _VPNCreditVault.contract, event: "IdentityCharged", logs: logs, sub: sub}, nil
}

// WatchIdentityCharged is a free log subscription operation binding the contract event 0xb9cf8c9dbbc25fc6c2c7a0a87ca2ccb300ef8c27ca5b1879072585f93143159f.
//
// Solidity: event IdentityCharged(bytes32 indexed chargeId, address indexed payer, address indexed identity, uint256 amount)
func (_VPNCreditVault *VPNCreditVaultFilterer) WatchIdentityCharged(opts *bind.WatchOpts, sink chan<- *VPNCreditVaultIdentityCharged, chargeId [][32]byte, payer []common.Address, identity []common.Address) (event.Subscription, error) {

	var chargeIdRule []interface{}
	for _, chargeIdItem := range chargeId {
		chargeIdRule = append(chargeIdRule, chargeIdItem)
	}
	var payerRule []interface{}
	for _, payerItem := range payer {
		payerRule = append(payerRule, payerItem)
	}
	var identityRule []interface{}
	for _, identityItem := range identity {
		identityRule = append(identityRule, identityItem)
	}

	logs, sub, err := _VPNCreditVault.contract.WatchLogs(opts, "IdentityCharged", chargeIdRule, payerRule, identityRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(VPNCreditVaultIdentityCharged)
				if err := _VPNCreditVault.contract.UnpackLog(event, "IdentityCharged", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseIdentityCharged is a log parse operation binding the contract event 0xb9cf8c9dbbc25fc6c2c7a0a87ca2ccb300ef8c27ca5b1879072585f93143159f.
//
// Solidity: event IdentityCharged(bytes32 indexed chargeId, address indexed payer, address indexed identity, uint256 amount)
func (_VPNCreditVault *VPNCreditVaultFilterer) ParseIdentityCharged(log types.Log) (*VPNCreditVaultIdentityCharged, error) {
	event := new(VPNCreditVaultIdentityCharged)
	if err := _VPNCreditVault.contract.UnpackLog(event, "IdentityCharged", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// VPNCreditVaultOwnershipTransferredIterator is returned from FilterOwnershipTransferred and is used to iterate over the raw logs and unpacked data for OwnershipTransferred events raised by the VPNCreditVault contract.
type VPNCreditVaultOwnershipTransferredIterator struct {
	Event *VPNCreditVaultOwnershipTransferred // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *VPNCreditVaultOwnershipTransferredIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(VPNCreditVaultOwnershipTransferred)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(VPNCreditVaultOwnershipTransferred)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *VPNCreditVaultOwnershipTransferredIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *VPNCreditVaultOwnershipTransferredIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// VPNCreditVaultOwnershipTransferred represents a OwnershipTransferred event raised by the VPNCreditVault contract.
type VPNCreditVaultOwnershipTransferred struct {
	PreviousOwner common.Address
	NewOwner      common.Address
	Raw           types.Log // Blockchain specific contextual infos
}

// FilterOwnershipTransferred is a free log retrieval operation binding the contract event 0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0.
//
// Solidity: event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)
func (_VPNCreditVault *VPNCreditVaultFilterer) FilterOwnershipTransferred(opts *bind.FilterOpts, previousOwner []common.Address, newOwner []common.Address) (*VPNCreditVaultOwnershipTransferredIterator, error) {

	var previousOwnerRule []interface{}
	for _, previousOwnerItem := range previousOwner {
		previousOwnerRule = append(previousOwnerRule, previousOwnerItem)
	}
	var newOwnerRule []interface{}
	for _, newOwnerItem := range newOwner {
		newOwnerRule = append(newOwnerRule, newOwnerItem)
	}

	logs, sub, err := _VPNCreditVault.contract.FilterLogs(opts, "OwnershipTransferred", previousOwnerRule, newOwnerRule)
	if err != nil {
		return nil, err
	}
	return &VPNCreditVaultOwnershipTransferredIterator{contract: _VPNCreditVault.contract, event: "OwnershipTransferred", logs: logs, sub: sub}, nil
}

// WatchOwnershipTransferred is a free log subscription operation binding the contract event 0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0.
//
// Solidity: event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)
func (_VPNCreditVault *VPNCreditVaultFilterer) WatchOwnershipTransferred(opts *bind.WatchOpts, sink chan<- *VPNCreditVaultOwnershipTransferred, previousOwner []common.Address, newOwner []common.Address) (event.Subscription, error) {

	var previousOwnerRule []interface{}
	for _, previousOwnerItem := range previousOwner {
		previousOwnerRule = append(previousOwnerRule, previousOwnerItem)
	}
	var newOwnerRule []interface{}
	for _, newOwnerItem := range newOwner {
		newOwnerRule = append(newOwnerRule, newOwnerItem)
	}

	logs, sub, err := _VPNCreditVault.contract.WatchLogs(opts, "OwnershipTransferred", previousOwnerRule, newOwnerRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(VPNCreditVaultOwnershipTransferred)
				if err := _VPNCreditVault.contract.UnpackLog(event, "OwnershipTransferred", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseOwnershipTransferred is a log parse operation binding the contract event 0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0.
//
// Solidity: event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)
func (_VPNCreditVault *VPNCreditVaultFilterer) ParseOwnershipTransferred(log types.Log) (*VPNCreditVaultOwnershipTransferred, error) {
	event := new(VPNCreditVaultOwnershipTransferred)
	if err := _VPNCreditVault.contract.UnpackLog(event, "OwnershipTransferred", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}
