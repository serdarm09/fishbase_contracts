require('dotenv').config({ path: '.env' });

module.exports = [process.env.BOOST_BASE_URI || '', process.env.CONTRACT_OWNER || ''];
