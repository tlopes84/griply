const jwt = require('jsonwebtoken');
function validarToken(req, res, next) {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({error:'Token ausente'});
  try {
    req.userId = jwt.verify(token, process.env.JWT_SECRET).id;
    next();
  } catch {
    res.status(401).json({error:'Token inválido'});
  }
}
module.exports = { validarToken };
