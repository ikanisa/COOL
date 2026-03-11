const rayonSportsMomoCode = '008000';
const rayonSportsMomoCountryCode = 'RW';
const rayonSportsMomoUssdPattern = '*182*8*1*$rayonSportsMomoCode*[amount]#';

String rayonSportsMomoUssd(int amount) {
  return '*182*8*1*$rayonSportsMomoCode*$amount#';
}
