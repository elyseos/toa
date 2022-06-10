const ethers = require('ethers')
const abi = require('../lib/abi')
const bytecode = require('../lib/bytecode')
const assert = require('assert');
const privateKeys = require('../lib/pks')

const rpcEndPoint = 'https://xapi.testnet.fantom.network/lachesis'
const provider = new ethers.providers.JsonRpcProvider(rpcEndPoint)

const ownerWallet = new ethers.Wallet(privateKeys[0],provider)

const usdcAddress = '0x9b76deD4C2386E214dB5B6B70Dd26c37abf39E13'

const usdcContract = (pk) => {
    let w = new ethers.Wallet(pk,provider)
    return ethers.Contract(usdcAddress, abi.usdc, w)
}

const toBN = (n,dec) => {
    if(dec===undefined) return ethers.BigNumber.from(n.toString())
    let fAr = parseFloat(n).toString().split('.')
    let bn
    if(fAr.length===1){
        bn = ethers.BigNumber.from(n.toString())
    } else {
        dec -= fAr[1].length
        bn = ethers.BigNumber.from(fAr.join(''))
    }
    let d = ethers.BigNumber.from((10**dec).toString())
    return bn.mul(d)
}

const confirm = (txhash) => {
    return new Promise(r=>provider.once(txhash,()=>r()))
}

const deployTOA = async () => {
    const factory = new ethers.ContractFactory(abi.toa, bytecode.toa.object, ownerWallet)
    const contract = await factory.deploy('');
    console.log('..awaiting confirmation')
    await confirm(contract.deployTransaction.hash)
    return contract.address;
} 

/*

const contract = new ethers.Contract(address, abi, wallet)
*/

const toaAllocations = (total, percentages) => {
    return {total,alloc:percentages.map(n=>n*total/100)}
}

const deploy = async () => {
    
    try{
        console.log('deploying toa')
        let toaAddress = await deployTOA();
        console.log('deploying crowdsale')
        const factory = new ethers.ContractFactory(abi.crowdsale, bytecode.crowdsale.object, ownerWallet)
        
        let numTOAs = 100
        let price = toBN(1000,6)
        let toaAlloc = [60,25,2,5,5,21].map(n=>toBN(n))
        let fundAlloc = [91,3,3,3].map(n=>toBN(n))
        const contract = await factory.deploy(
            usdcAddress,
            toaAddress,
            toBN(10).mul(price),
            toBN(180),
            price,
            toaAlloc,
            fundAlloc,
            toBN(180*2)
        );
        console.log('..awaiting confirmation')
        await confirm(contract.deployTransaction.hash)
        return {toaAddress: toaAddress, crowdsaleAddress: contract.address}
    }
    catch(e){
        console.log(e)
    }
    return null
}

const changeTOAOwner = async (toaAddress,newAddress) => {
    console.log('changing TOA Owner')
    const contract = new ethers.Contract(toaAddress, abi.toa, ownerWallet)
    let ret = await contract.transferOwnership(newAddress)
    console.log('..awaiting confirmation')
    await confirm(ret.hash)
    let owner = await contract.owner()
    assert(owner==newAddress,"Change Owner failed")
}

const start = async (crowdsaleAddress) => {
    try{
        console.log('starting crowdsale')
        const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, ownerWallet)
        let ret = await contract.start()
        console.log('..awaiting confirmation')
        await confirm(ret.hash)
        let tm = await contract.timeUntilEnd()
        assert(tm.gt(toBN(0)),"Invalid time until end")
        console.log(tm + '')
    }
    catch(e){
        console.log(e)
    }
}

const wait = (n) => {
    return new Promise(r=>setTimeout(()=>r(),n))
}

const run = async () => {
   let ret = await deploy()
   assert((ret),"Deploy Failed")
   await changeTOAOwner(ret.toaAddress, ret.crowdsaleAddress)
   await start(ret.crowdsaleAddress)
   return 'done'
}

run().then(console.log)
