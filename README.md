# ERC721A with beta claim optimization
OtherSide Meta smart-contract corrected with optimization

### Problem
![Twitter](https://i.imgur.com/eBBqagC.png)


### Official Otherdeed (OTHR) contract deployed on ETH mainnet

🌎 https://etherscan.io/address/0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258#code


### Optimizations made

- ERC720 > ERC720A (https://github.com/chiru-labs/ERC721A/releases/tag/v3.2.0)
---> removes an extra storage write when minting multiple tokens and enumerability
- Removed non-mint related code just for testing purposes
- mint price a constant 

✅ 50% reduction just by doing this, this could have save 💸 +50M$ in gas fees for users



[Twitter]: https://twitter.com/search?q=yuga%20erc721a%20gas&src=typed_query&f=top
