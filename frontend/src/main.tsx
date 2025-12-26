import React, { useState } from 'react'
import ReactDOM from 'react-dom/client'
import { ShoppingCart, Activity, Server, Package, CheckCircle, AlertCircle } from 'lucide-react'

const App = () => {
    const [sku, setSku] = useState('LOCAL-TEST-SKU')
    const [quantity, setQuantity] = useState(1)
    const [logs, setLogs] = useState<{time: string, msg: string, type: 'info' | 'success' | 'error'}[]>([])
    const [loading, setLoading] = useState(false)

    const addLog = (msg: string, type: 'info' | 'success' | 'error' = 'info') => {
        setLogs(prev => [{ time: new Date().toLocaleTimeString(), msg, type }, ...prev])
    }

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        setLoading(true)
        addLog(`Submitting order for ${quantity}x ${sku}...`, 'info')

        try {
            // In Docker/K8s, Nginx proxies /api to the Java service
            const response = await fetch('/api/inventory-update', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sku, quantity })
            })

            if (response.ok) {
                addLog(`Order accepted! Status: ${response.status}`, 'success')
            } else {
                const errorText = await response.text()
                addLog(`Order failed: ${response.status} - ${errorText}`, 'error')
            }
        } catch (error) {
            addLog(`Network Error: ${error}`, 'error')
        } finally {
            setLoading(false)
        }
    }

    return (
        <div className="min-h-screen bg-gray-900 text-gray-100 font-sans">
            {/* Header */}
            <header className="bg-gray-800 border-b border-gray-700 p-6">
                <div className="max-w-7xl mx-auto flex items-center justify-between">
                    <div className="flex items-center gap-3">
                        <div className="bg-blue-600 p-2 rounded-lg">
                            <ShoppingCart className="w-6 h-6 text-white" />
                        </div>
                        <h1 className="text-2xl font-bold text-white">Cloud-Native Order Dashboard</h1>
                    </div>
                    <div className="flex items-center gap-4 text-sm text-gray-400">
                        <div className="flex items-center gap-2">
                            <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></div>
                            <span>System Operational</span>
                        </div>
                        <span>v2.4.0-canary</span>
                    </div>
                </div>
            </header>

            <main className="max-w-7xl mx-auto p-6 grid grid-cols-1 lg:grid-cols-2 gap-8">
                {/* Order Form */}
                <section className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden shadow-xl">
                    <div className="p-6 border-b border-gray-700 flex items-center gap-3">
                        <Package className="w-5 h-5 text-blue-400" />
                        <h2 className="text-lg font-semibold">New Order Ingestion</h2>
                    </div>
                    <div className="p-6">
                        <form onSubmit={handleSubmit} className="space-y-6">
                            <div>
                                <label className="block text-sm font-medium text-gray-400 mb-2">Stock Keeping Unit (SKU)</label>
                                <input
                                    type="text"
                                    value={sku}
                                    onChange={(e) => setSku(e.target.value)}
                                    className="w-full bg-gray-900 border border-gray-600 rounded-lg px-4 py-3 text-white focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                                    placeholder="e.g. PROD-123"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-gray-400 mb-2">Quantity</label>
                                <input
                                    type="number"
                                    min="1"
                                    value={quantity}
                                    onChange={(e) => setQuantity(parseInt(e.target.value))}
                                    className="w-full bg-gray-900 border border-gray-600 rounded-lg px-4 py-3 text-white focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                                />
                            </div>

                            <button
                                type="submit"
                                disabled={loading}
                                className={`w-full py-3 px-4 rounded-lg font-medium flex items-center justify-center gap-2 transition-all ${
                                    loading
                                        ? 'bg-gray-700 text-gray-400 cursor-not-allowed'
                                        : 'bg-blue-600 hover:bg-blue-700 text-white shadow-lg hover:shadow-blue-500/20'
                                }`}
                            >
                                {loading ? (
                                    <Activity className="w-5 h-5 animate-spin" />
                                ) : (
                                    <Server className="w-5 h-5" />
                                )}
                                {loading ? 'Processing...' : 'Submit Order Event'}
                            </button>
                        </form>
                    </div>
                    <div className="bg-gray-900/50 p-4 border-t border-gray-700">
                        <p className="text-xs text-gray-500 text-center">
                            Event will be pushed to <code>order-processing-queue</code> via Java Service
                        </p>
                    </div>
                </section>

                {/* Live Logs */}
                <section className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden shadow-xl flex flex-col h-[500px]">
                    <div className="p-6 border-b border-gray-700 flex items-center justify-between">
                        <div className="flex items-center gap-3">
                            <Activity className="w-5 h-5 text-green-400" />
                            <h2 className="text-lg font-semibold">Client-Side Activity Log</h2>
                        </div>
                        <button onClick={() => setLogs([])} className="text-xs text-gray-400 hover:text-white">Clear</button>
                    </div>
                    <div className="flex-1 overflow-y-auto p-4 space-y-3 font-mono text-sm bg-gray-900">
                        {logs.length === 0 && (
                            <div className="h-full flex flex-col items-center justify-center text-gray-600 gap-2">
                                <Activity className="w-8 h-8 opacity-20" />
                                <p>Waiting for events...</p>
                            </div>
                        )}
                        {logs.map((log, i) => (
                            <div key={i} className="flex gap-3 animate-in fade-in slide-in-from-bottom-2">
                                <span className="text-gray-500 shrink-0">[{log.time}]</span>
                                <div className="flex items-start gap-2">
                                    {log.type === 'success' && <CheckCircle className="w-4 h-4 text-green-500 mt-0.5" />}
                                    {log.type === 'error' && <AlertCircle className="w-4 h-4 text-red-500 mt-0.5" />}
                                    <span className={`${
                                        log.type === 'success' ? 'text-green-400' :
                                            log.type === 'error' ? 'text-red-400' : 'text-gray-300'
                                    }`}>
                    {log.msg}
                  </span>
                                </div>
                            </div>
                        ))}
                    </div>
                </section>
            </main>
        </div>
    )
}

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>
)