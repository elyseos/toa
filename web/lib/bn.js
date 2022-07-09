import {ethers} from "ethers"

export const toBN = (n,dec) => {
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
export const toDec = (n, dec, show) => {
    
    let nmAr = (parseInt(n.toString())/(10**dec)).toString().split('.')
    if(nmAr.length===1) return nmAr[0]
    nmAr[1] = nmAr[1].substring(0,show)
    return nmAr.join('.')
}
