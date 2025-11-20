package analysis

import "math"

type MetricsSample struct {
	Latency    float64
	Jitter     float64
	PacketLoss float64
	Bandwidth  float64
}

func ZScore(value, mean, stddev float64) float64 {
	if stddev == 0 {
		return 0
	}
	return (value - mean) / stddev
}

func DetectLatencySpike(sample MetricsSample, mean, stddev float64) bool {
	return math.Abs(ZScore(sample.Latency, mean, stddev)) > 3
}

func DetectPacketLoss(sample MetricsSample, threshold float64) bool {
	return sample.PacketLoss > threshold
}