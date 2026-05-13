nim c --threadAnalysis:off --gc:markAndSweep -o:skybook src/skybook.nim
echo "Compile frontend..."
nim js --hint[Path]:off -o:src/frontend/app.js src/frontend/app.nim
exec ./skybook
