const ethers = require('ethers')
const abi = require('../lib/abi')
const bytecode = require('../lib/bytecode')
//const assert = require('assert');
const privateKeys = require('../lib/pks')
const { forEach } = require('../lib/pks')
const { exit } = require('process');
const cliProgress = require('cli-progress')

const rpcEndPoint = 'https://xapi.testnet.fantom.network/lachesis'
const provider = new ethers.providers.JsonRpcProvider(rpcEndPoint)

let crowdsaleAddress = ''
let toaAddress = ''

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
    beneficiaries: 60,
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

const assert = (condition,msg) => {
    if(!condition){
        console.log(msg)
        exit()
    }
    return
}

const numTOAs = () => {
    let num = 0
    Object.keys(allocation).forEach(a=>num+=allocation[a])
    return num
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
            allocation.beneficiaries,
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
            toBN(8).mul(price),
            toBN(60),
            price,
            toaAlloc,
            fundAlloc,
            toBN(80)
        );
        await confirm(contract.deployTransaction.hash)
        return {toaAddress: toaAddress, crowdsaleAddress: contract.address}
    }
    catch(e){
        console.log(e)
        exit()
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
        exit()
    }
}

const wait = (n) => {
    const bar1 = new cliProgress.SingleBar({}, cliProgress.Presets.shades_classic)
    bar1.start(n/1000, 0);
    let tm = 0
    let interval = setInterval(()=>{
        tm+=1
        bar1.update(tm)
    },1000)
    return new Promise(r=>setTimeout(()=>{
        clearInterval(interval)
        bar1.update(n/1000)
        bar1.stop()
        r()
    },n))
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

const checkTOABalances = async (remainder) => {
    console.log('remainder = ' + remainder)
    console.log('checking initial TOA balances')
    let checkTOABal = async (user,checkRemainder) => {
        try{
            let bal = await checkTOABalance(users[user])
            let alloc = toBN(allocation[user])
            if(checkRemainder) alloc = alloc.add(toBN(remainder))
            console.log('bal + remainder: ' + bal)
            assert(bal.eq(alloc),user + " balance incorrect. = " + bal + ',should be ' + alloc)
        }
        catch(e){
            assert(false,e.message)
        }
    }
    
    
    await Promise.all([
        checkTOABal('guardian'),
        checkTOABal('rainmaker'),
        checkTOABal('bonus',true),
        checkTOABal('concierge'),
        checkTOABal('wisdom')
    ])
    /*
    await checkTOABal('guardian')
    await checkTOABal('rainmaker')
    await checkTOABal('bonus',true) //,remainder),
    await checkTOABal('concierge')
    await checkTOABal('wisdom')
    */
}

const setAllocationAddress = async (user) => {
    console.log('setting allocation address for ' + user)
    let idx = toBN(allocIDX[user])
    let userWallet = new ethers.Wallet(users[user],provider)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, ownerWallet)
    let ret = await contract.setAllocationAddress(idx,userWallet.address)
    await confirm(ret.hash)
    
    /*
    console.log('checking assignments')
    let _idx = await contract.assignmentIdx(userWallet.address)
    assert(idx.eq(_idx),'Incorrect idx. Is ' + _idx + ', should be ' + idx)
    let address = await contract.assignmentAddress(idx)
    assert(address==userWallet.address,'Incorrect address. Is ' + address + ',should be ' + userWallet.address)
    let isAcc = await contract.isAssigned(userWallet.address)
    assert(isAcc,'Account not asigned')
    */
    
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

const getTOABalance = async (address) => {
    const contract = new ethers.Contract(toaAddress, abi.toa, ownerWallet)
    return await contract.balanceOf(address)
}

const assignTOA = async (pk,user) => {
    let userWallet = new ethers.Wallet(pk,provider)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, userWallet)
    user = user || userWallet.address
    console.log('..assigning TOA to ' + user)
    try{
        let available = await checkTOABalance(pk)
        let ret = await contract.assignTOAs(userWallet.address)
        await confirm(ret.hash)
        let bal = await getTOABalance(userWallet.address)
        console.log('Balance for ' + user + ': ' + bal)
        assert(bal.eq(available),'incorrect balance for ' + user)
        bal = await checkTOABalance(pk)
        assert(bal.eq(toBN(0)),'balance should be zero')
    }
    catch(e){
        assert(false,e.message)
    }
}


const buy = async (user, num, checkBalBefore) => {
    console.log('buying ' + num + ' TOA' + ((num>1)?'s':''))
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

const succesfulCampaign = async (buyers) => {
    console.log('*simulating succesful campaign*')
    let sold = 0
    await buy(buyers[0].buyer,buyers[0].amount)
    sold += buyers[0].amount
    //await buy(users.beneficiaries[0],1,true)
    //await buy(users.beneficiaries[2],5)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, ownerWallet)
    let tm = await contract.timeUntilEnd()
    console.log('time to end: ' + tm)
    tm = tm.add(toBN(20))
    console.log('waiting ' + tm + ' secs')
    await wait(tm.toNumber()*1000)
    try{
        let isSuccess = await contract.isSuccess()
        assert(isSuccess, 'campaign failed :(')
        console.log('campaign succesful')
    }
    catch(e){
        assert(false,e.message)
    }
    return sold
}

const failCampaign = async (buyers) => {
    console.log('*simulating failure campaign*')
    let sold = 0
    await buy(buyers[0].buyer,buyers[0].amount)
    sold += buyers[0].amount
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, ownerWallet)
    let tm = await contract.timeUntilEnd()
    console.log('time to end: ' + tm)
    tm = tm.add(toBN(20))
    console.log('waiting ' + tm + ' secs')
    await wait(tm.toNumber()*1000)
    try{
        let isSuccess = await contract.isSuccess()
        assert(!isSuccess,'Campain should have failed')
    }
    catch(e){
        assert(true,'Campain should have failed')
    }
    console.log('Campaign failed')
    return sold
}

const USDCBal = async (address) => {
    const contract = new ethers.Contract(usdcAddress, abi.usdc, ownerWallet)
    return await contract.balanceOf(address)
}

const fundsRaised = async () => {
    console.log('getting funds raised')
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, ownerWallet)
    let funds = await contract.fundsRaised()
    let bal = await USDCBal(crowdsaleAddress)
    assert(funds.eq(bal),'imbalance in funds raised vs actual balance')
    console.log('..funds raised: ' + funds)
    return funds
}

const assignFunds = async (user, totalFunds) => {
    
    console.log('assigning funds to ' + user)
    const userWallet = new ethers.Wallet(users[user],provider)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, userWallet)
    let expectedBalance = toBN(fundPerc[user]).mul(totalFunds).div(toBN(100))
    let bal = await contract.balanceOf(userWallet.address)
    assert(bal.eq(expectedBalance),'Unexpected balance. Is ' + bal + ', sould be ' + expectedBalance)
    let userBal = await USDCBal(userWallet.address)
    try{
        let ret = await contract.withdrawFunds(userWallet.address)
        await confirm(ret.hash)
        let newBalance = await USDCBal(userWallet.address)
        assert(userBal.add(expectedBalance).eq(newBalance),'Balance incorrect. Is ' + newBalance + ', should be ' + (userBal.add(expectedBalance)))
    }
    catch(e){
        console.log(e.message)
        exit()
    }
}

const returnFunds = async(buyer) => {
    console.log('returning funds to ' + buyer.buyer)
    const userWallet = new ethers.Wallet(buyer.buyer,provider)
    const contract = new ethers.Contract(crowdsaleAddress, abi.crowdsale, userWallet)
    let amnt = toBN(1000,6).mul(toBN(buyer.amount))
    let userBal = await USDCBal(userWallet.address)
    try{
        let ret = await contract.returnFunds(userWallet.address)
        await confirm(ret.hash)
        let newBal = await USDCBal(userWallet.address)
        assert(userBal.add(amnt).eq(newBal),"Incorrect balance. Got " + newBal + ', should be ' + userBal.add(amnt))
    }
    catch(e){
        assert(false,e.message)
    }
    return
}

const runSuccess = async () => {
    let ret = await deploy()
    assert((ret),"Deploy Failed")
    await changeTOAOwner(ret.toaAddress, ret.crowdsaleAddress)
    crowdsaleAddress = ret.crowdsaleAddress
    console.log('crowdsale contract address: ' + crowdsaleAddress)
    toaAddress = ret.toaAddress
    
    await start()
    let buyers = [
        {buyer: users.beneficiaries[0], amount: 9}
    ]
    let numSold = await succesfulCampaign(buyers)
    await setAllocationAddresses()
    //await checkTOABalances(allocation['beneficiaries']-numSold)
    
    console.log('assigning toas')
    await assignTOA(buyers[0].buyer)
    await assignTOA(users['guardian'],'guardian')
    await assignTOA(users['rainmaker'],'rainmaker')
    await assignTOA(users['bonus'],'bonus')
    await assignTOA(users['concierge'],'concierge')
    await assignTOA(users['wisdom'],'wisdom')

    let funds = await fundsRaised()
    await assignFunds('producer',funds)
    await assignFunds('platform',funds)
    await assignFunds('reserve',funds)
    await assignFunds('auditor',funds)
    
    return 'done'
    
}

const runFail = async () => {
    let ret = await deploy()
    assert((ret),"Deploy Failed")
    await changeTOAOwner(ret.toaAddress, ret.crowdsaleAddress)
    crowdsaleAddress = ret.crowdsaleAddress
    console.log('crowdsale contract address: ' + crowdsaleAddress)
    toaAddress = ret.toaAddress
    
    await start()
    let buyers = [
        {buyer: users.beneficiaries[0], amount: 7}
    ]
    await failCampaign(buyers)
    await returnFunds(buyers[0])
    return 'done'
}

runFail().then(console.log)
