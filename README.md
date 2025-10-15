# GagaFX - Professional MetaTrader 5 Expert Advisor

A sophisticated MetaTrader 5 Expert Advisor featuring AI-powered predictions, Break of Structure (BOS) analysis, and a modern HUD interface. Built with professional-grade risk management and multi-timeframe analysis.

## 🚀 Features

- **AI Predictions**: Machine learning-based price movement predictions (+1, +2, +3 bars)
- **Break of Structure (BOS)**: Advanced market structure analysis
- **Multi-Timeframe Context**: HTF bias analysis across M5, M15, M30, H1
- **Professional HUD**: Clean, responsive interface with proper positioning
- **Risk Management**: Dynamic position sizing, trailing stops, partial closes
- **Session & News Filters**: Smart trading time and news event filtering
- **Real-time Monitoring**: Live prediction updates and trade tracking

## 📊 Technical Indicators

- **Trend**: EMA (50/200), SMA (20/100)
- **Momentum**: RSI (14), TSI (25/13/7)
- **Volatility**: ATR (14) for stops and position sizing
- **Structure**: Pivot-based swing analysis with BOS detection

## 🎯 HUD Interface

The EA features a professional HUD with:
- **Top-right panel**: Trading controls, risk info, and status
- **Bottom-right widget**: Real-time prediction probabilities
- **Responsive design**: Adapts to different screen sizes and DPI settings
- **Theme-aware**: Automatic dark/light mode detection

## 📁 Project Structure

- `MQL5/Experts/GagaFX.mq5` — Main Expert Advisor
- `MQL5/Files/` — Runtime data files (CSV logs, JSON exports)
- `MQL5/Include/` — Shared headers and utilities
- `templates/` — MQL5 script templates
- `tools/` — Deployment and utility scripts

## ⚙️ Installation & Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/guyshonshon/gagafx.git
   cd gagafx
   ```

2. **Deploy to MetaTrader 5**:
   - Open MetaTrader 5 → File → Open Data Folder
   - Run: `bash tools/deploy.sh --data-dir "/path/to/Data Folder"`
   - Or use symlinks for live development: `bash tools/deploy.sh --symlink`

3. **Compile in MetaEditor**:
   - Open MetaEditor from MetaTrader 5
   - Open `MQL5/Experts/GagaFX.mq5`
   - Compile (F7) and attach to chart

## 🎛️ Configuration

The EA features organized input parameters:
- **Basic Parameters**: Symbol, timeframe, magic number
- **Risk & Execution**: Position sizing, spread limits, slippage
- **Filters**: Session times, news blocking
- **Indicators**: EMA, RSI, ATR periods and thresholds
- **Stops/Targets**: ATR multipliers, partial closes, trailing stops
- **Prediction Gate**: AI threshold, calibration settings

## 📈 Usage

1. **Attach to Chart**: Drag GagaFX.mq5 to your desired chart
2. **Configure Parameters**: Press F7 to open Properties dialog
3. **Monitor HUD**: Watch the top-right panel for status and controls
4. **View Predictions**: Check bottom-right widget for AI predictions
5. **Control Trading**: Use START/STOP and Gate buttons on HUD

## 🔧 Development

- **Code Style**: 4 spaces, LF endings (see `.editorconfig`)
- **File Structure**: Organized MQL5 standard layout
- **Version Control**: Git with proper `.gitignore` for MQL5
- **Deployment**: Automated scripts for easy MT5 integration

## 📝 License

This project is open source. Please check the license file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.
