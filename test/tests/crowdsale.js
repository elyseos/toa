const ethers = require('ethers')
const abi = require('../lib/abi')
const bytecode = require('../lib/bytecode')
const assert = require('assert');
const privateKeys = require('../lib/pks');
const { forEach } = require('../lib/pks');

const rpcEndPoint = 'https://xapi.testnet.fantom.network/lachesis'
const provider = new ethers.providers.JsonRpcProvider(rpcEndPoint)

let crowdsaleAddress = ''

let users = {
    owner: privateKeys[0],
    producer: privateKeys[1],
    platform: privateKeys[2],
    reserve: privateKeys[3],
    auditor: privateKeys[4],
    guardian: privateKeys[5],
    rainmaker: privateKeys[6],
    bonus: privateKeys[7],
    concierge: privateKeys[8],
    wisdom: privateKeys[9],
    beneficiaries: privateKeys.slice(10)
}

let allocIDX = {
    producer: 0,
    platform: 1,
    reserve: 2,
    auditor: 3,
    guardian: 4,
    rainmaker: 5,
    bonus: 6,
    concierge: 7,
    wisdom: 8
}

let allocation = {
    benificiaries: 60,
    guardian: 25,
    rainmaker: 2,
    bonus: 5,
    concierge: 5,
    wisdom: 21
}

let fundPerc = {
    producer: 91,
    platform: 3,
    reserve: 3,
    auditor: 3
}

const ownerWallet = new ethers.Wallet(users.owner,provider)

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
    console.log('....awaiting confirmation')
    return new Promise(r=>provider.once(txhash,()=>r()))
}

const deployTOA = async () => {
    const factory = new ethers.ContractFactory(abi.toa, bytecode.toa.object, ownerWallet)
    const contract = await factory.deploy('');
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
        let toaAlloc = [
            allocation.benificiaries,
            allocation.guardian,
            allocation.rainmaker,
            allocation.bonus,
            allocation.concierge,
            allocation.wisdom
        ].map(n=>toBN(n))
        let fundAlloc = [
            fundPerc.producer,
            fundPerc.platform,
            fundPerc.reserve,
            fundPerc.auditor
        ].map(n=>toBN(n))
        const contract = await factory.deploy(
            usdcAddress,
            toaAddress,
            toBN(10).mul(price),
            toBN(300),
            price,
            toaAlloc,
            fundAlloc,
            toBN(420)
        );
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
    await confirm(ret.hash)
    let owner = await contract.owner()
    assert(owner==newAddress,"Change Owner failed")
}

const start = async () => {
    try{
        console.log('starting crowdsale')
        const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, ownerWallet)
        let ret = await contract.start()
        await confirm(ret.hash)
        let tm = await contract.timeUntilEnd()
        assert(tm.gt(toBN(0)),"Invalid time until end")

        let isOpen = await contract.isOpen()
        assert(isOpen,"Contract not open")
    }
    catch(e){
        console.log(e)
    }
}

const wait = (n) => {
    return new Promise(r=>setTimeout(()=>r(),n))
}

const mintUSDC = async (user, amount) => {
    console.log('..minting USDC')
    const userWallet = new ethers.Wallet(user,provider)
    const contract = new ethers.Contract(usdcAddress, abi.usdc, userWallet)
    let ret = await contract.mint(userWallet.address,amount)
    await confirm(ret.hash)
    console.log('..approving spend')
    ret = await contract.approve(crowdsaleAddress, amount)
    await confirm(ret.hash)
}

const checkTOABalance = async (user) => {
    const userWallet = new ethers.Wallet(user,provider)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, userWallet)
    console.log('..checking toa balance of ' + userWallet.address)
    let bal = await contract.TOABalance(userWallet.address)
    return bal
}

const checkInitialTOABalances = async () => {
    let allocation = {
        benificiaries: 60,
        guardian: 25,
        rainmaker: 2,
        bonus: 5,
        concierge: 5,
        wisdom: 21
    }
    console.log('checking initial TOA balances')
    let checkTOABal = async (user) => {
        try{
            let bal = await checkTOABalance(users[user])
            assert(bal.eq(allocation[user]),user + " balance incorrect. = " + bal + ',should be ' + allocation[user])
        }
        catch(e){
            assert(false,e.message)
        }
    }
    await Promise.all([
        checkTOABal('guardian'),
        checkTOABal('rainmaker'),
        checkTOABal('bonus'),
        checkTOABal('concierge'),
        checkTOABal('wisdom')
    ])
}

const setAllocationAddress = async (user) => {
    console.log('setting allocation address for ' + user)
    let idx = toBN(allocIDX[user])
    let userWallet = new ethers.Wallet(users[user],provider)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, ownerWallet)
    let ret = await contract.setAllocationAddress(idx,userWallet.address)
    await confirm(ret.hash)
}

const setAllocationAddresses = async () => {
    await setAllocationAddress('producer')
    await setAllocationAddress('platform')
    await setAllocationAddress('reserve')
    await setAllocationAddress('auditor')
    await setAllocationAddress('guardian')
    await setAllocationAddress('rainmaker')
    await setAllocationAddress('bonus')
    await setAllocationAddress('concierge')
    await setAllocationAddress('wisdom')
}

const buy = async (user, num, checkBalBefore) => {
    console.log('buying ' + num + 'TOA' + ((num>1)?'s':''))
    let amnt = toBN(1000,6).mul(num)
    let numTOAs = toBN(num)
    const userWallet = new ethers.Wallet(user,provider)
    await mintUSDC(user, amnt)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, userWallet)
    console.log('..executing buy')
    try{
        let balBefore = toBN(0)
        if(checkBalBefore){
            balBefore = await checkTOABalance(user)
            console.log('..previous balance: ' + balBefore)
        }
        let ret = await contract.buy(numTOAs)
        await confirm(ret.hash)
        let bal = await checkTOABalance(user)
        let totalBal = numTOAs.add(balBefore)
        console.log('..total bal: ' + totalBal)
        assert(bal.eq(totalBal),"balance incorrect = " + bal + ' should be ' + totalBal)
    }
    catch(e){
        assert(false,e.message)
    }

}



const run = async () => {
   let ret = await deploy()
   assert((ret),"Deploy Failed")
   await changeTOAOwner(ret.toaAddress, ret.crowdsaleAddress)
   crowdsaleAddress = ret.crowdsaleAddress
   await start()
   await buy(users.beneficiaries[0],1)
   await buy(users.beneficiaries[0],2,true)
   //await setAllocationAddresses()
   //await checkInitialTOABalances()
   
   return 'done'
}

run().then(console.log)
